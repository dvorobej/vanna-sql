WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        SUM(p.p05) AS daily_amount,
        COUNT(*) AS daily_count,
        GROUP_CONCAT(DISTINCT p.p03) AS staff_ids,
        GROUP_CONCAT(DISTINCT st.o07) AS store_ids,
        COUNT(DISTINCT r.q03) AS distinct_films_count
    FROM pay p
    JOIN stf st ON st.o01 = p.p03
    LEFT JOIN ren r ON r.q01 = p.p04
    GROUP BY p.p02, DATE(p.p06)
),
window_stats AS (
    SELECT
        dp.customer_id,
        dp.payment_date,
        SUM(dp.daily_amount) OVER (PARTITION BY dp.customer_id ORDER BY JULIANDAY(dp.payment_date) RANGE BETWEEN 6 PRECEDING AND CURRENT ROW) AS window_amount,
        SUM(dp.daily_count) OVER (PARTITION BY dp.customer_id ORDER BY JULIANDAY(dp.payment_date) RANGE BETWEEN 6 PRECEDING AND CURRENT ROW) AS window_count,
        AVG(dp.daily_amount) OVER (PARTITION BY dp.customer_id ORDER BY JULIANDAY(dp.payment_date) RANGE BETWEEN 36 PRECEDING AND 7 PRECEDING) AS hist_avg_amount,
        GROUP_CONCAT(dp.staff_ids) OVER (PARTITION BY dp.customer_id ORDER BY JULIANDAY(dp.payment_date) RANGE BETWEEN 6 PRECEDING AND CURRENT ROW) AS window_staffs,
        GROUP_CONCAT(dp.store_ids) OVER (PARTITION BY dp.customer_id ORDER BY JULIANDAY(dp.payment_date) RANGE BETWEEN 6 PRECEDING AND CURRENT ROW) AS window_stores,
        SUM(dp.distinct_films_count) OVER (PARTITION BY dp.customer_id ORDER BY JULIANDAY(dp.payment_date) RANGE BETWEEN 6 PRECEDING AND CURRENT ROW) AS window_films
    FROM daily_payments dp
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
    WHERE ws.window_amount >= 3 * ws.hist_avg_amount
      AND ws.window_count >= 5
)
SELECT
    customer_name,
    country,
    city,
    payment_date,
    window_amount,
    window_count,
    window_staffs,
    window_stores,
    window_films,
    RANK() OVER (ORDER BY window_amount DESC) AS global_suspicious_rank
FROM suspicious_cases
ORDER BY window_amount DESC;