WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        SUM(p.p05) AS daily_amount,
        COUNT(*) AS daily_count,
        GROUP_CONCAT(DISTINCT p.p03) AS staff_ids,
        GROUP_CONCAT(DISTINCT st.o07) AS store_ids,
        GROUP_CONCAT(DISTINCT inv.n02) AS film_ids
    FROM pay p
    JOIN stf st ON st.o01 = p.p03
    JOIN ren r ON r.q01 = p.p04
    JOIN inv ON inv.n01 = r.q03
    GROUP BY p.p02, DATE(p.p06)
),
window_stats AS (
    SELECT
        customer_id,
        payment_date,
        SUM(daily_amount) OVER (PARTITION BY customer_id ORDER BY JULIANDAY(payment_date) RANGE BETWEEN 6 PRECEDING AND CURRENT ROW) AS window_amount,
        SUM(daily_count) OVER (PARTITION BY customer_id ORDER BY JULIANDAY(payment_date) RANGE BETWEEN 6 PRECEDING AND CURRENT ROW) AS window_count,
        AVG(daily_amount) OVER (PARTITION BY customer_id ORDER BY JULIANDAY(payment_date) RANGE BETWEEN 36 PRECEDING AND 7 PRECEDING) AS hist_avg_amount,
        AVG(daily_count) OVER (PARTITION BY customer_id ORDER BY JULIANDAY(payment_date) RANGE BETWEEN 36 PRECEDING AND 7 PRECEDING) AS hist_avg_count,
        COUNT(*) OVER (PARTITION BY customer_id ORDER BY JULIANDAY(payment_date) RANGE BETWEEN 36 PRECEDING AND 7 PRECEDING) AS hist_days_count,
        GROUP_CONCAT(staff_ids) OVER (PARTITION BY customer_id ORDER BY JULIANDAY(payment_date) RANGE BETWEEN 6 PRECEDING AND CURRENT ROW) AS window_staffs,
        GROUP_CONCAT(store_ids) OVER (PARTITION BY customer_id ORDER BY JULIANDAY(payment_date) RANGE BETWEEN 6 PRECEDING AND CURRENT ROW) AS window_stores,
        GROUP_CONCAT(film_ids) OVER (PARTITION BY customer_id ORDER BY JULIANDAY(payment_date) RANGE BETWEEN 6 PRECEDING AND CURRENT ROW) AS window_films
    FROM daily_payments
),
suspicious_cases AS (
    SELECT
        ws.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city
    FROM window_stats ws
    JOIN cus c ON c.h01 = ws.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
    WHERE hist_days_count >= 5
      AND window_amount >= 3 * hist_avg_amount
      AND window_count >= 5
)
SELECT
    customer_name,
    country,
    city,
    payment_date,
    window_amount,
    window_count,
    (SELECT COUNT(DISTINCT value) FROM json_each('["' || REPLACE(window_films, ',', '","') || '"]')) AS unique_films_count,
    window_staffs,
    window_stores,
    RANK() OVER (ORDER BY window_amount DESC) AS global_suspicious_rank
FROM suspicious_cases
ORDER BY window_amount DESC;