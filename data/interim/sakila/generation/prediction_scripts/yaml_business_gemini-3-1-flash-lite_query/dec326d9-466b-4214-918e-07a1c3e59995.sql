WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        SUM(p.p05) AS daily_amount,
        COUNT(*) AS daily_count,
        GROUP_CONCAT(DISTINCT p.p03) AS staff_ids,
        GROUP_CONCAT(DISTINCT st.o07) AS store_ids,
        COUNT(DISTINCT r.q03) AS film_count
    FROM pay p
    JOIN stf st ON st.o01 = p.p03
    LEFT JOIN ren r ON r.q01 = p.p04
    GROUP BY p.p02, DATE(p.p06)
),
window_stats AS (
    SELECT
        d1.customer_id,
        d1.payment_date AS window_end,
        SUM(d2.daily_amount) AS window_amount,
        SUM(d2.daily_count) AS window_count,
        GROUP_CONCAT(DISTINCT d2.staff_ids) AS staff_list,
        GROUP_CONCAT(DISTINCT d2.store_ids) AS store_list,
        SUM(d2.film_count) AS total_films
    FROM daily_payments d1
    JOIN daily_payments d2 ON d2.customer_id = d1.customer_id
        AND d2.payment_date BETWEEN DATE(d1.payment_date, '-6 days') AND d1.payment_date
    GROUP BY d1.customer_id, d1.payment_date
),
history_stats AS (
    SELECT
        d1.customer_id,
        d1.payment_date AS window_end,
        AVG(d2.daily_amount) AS hist_avg_amount,
        COUNT(d2.payment_date) AS hist_days
    FROM daily_payments d1
    JOIN daily_payments d2 ON d2.customer_id = d1.customer_id
        AND d2.payment_date BETWEEN DATE(d1.payment_date, '-30 days') AND DATE(d1.payment_date, '-1 day')
    GROUP BY d1.customer_id, d1.payment_date
    HAVING COUNT(d2.payment_date) >= 5
),
suspicious_cases AS (
    SELECT
        ws.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city
    FROM window_stats ws
    JOIN history_stats hs ON hs.customer_id = ws.customer_id AND hs.window_end = ws.window_end
    JOIN cus c ON c.h01 = ws.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
    WHERE ws.window_amount >= 3 * hs.hist_avg_amount
      AND ws.window_count >= 5
)
SELECT
    customer_name,
    country,
    city,
    window_end,
    window_amount,
    window_count,
    staff_list,
    store_list,
    total_films,
    RANK() OVER (ORDER BY window_amount DESC) AS global_suspicious_rank
FROM suspicious_cases
ORDER BY window_amount DESC;