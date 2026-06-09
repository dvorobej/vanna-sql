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
rolling_stats AS (
    SELECT
        dp.*,
        SUM(dp.daily_amount) OVER (PARTITION BY dp.customer_id ORDER BY dp.payment_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS window_amount_7d,
        SUM(dp.daily_count) OVER (PARTITION BY dp.customer_id ORDER BY dp.payment_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS window_count_7d,
        AVG(dp.daily_amount) OVER (PARTITION BY dp.customer_id ORDER BY dp.payment_date ROWS BETWEEN 37 PRECEDING AND 7 PRECEDING) AS hist_avg_amount_30d,
        AVG(dp.daily_count) OVER (PARTITION BY dp.customer_id ORDER BY dp.payment_date ROWS BETWEEN 37 PRECEDING AND 7 PRECEDING) AS hist_avg_count_30d
    FROM daily_payments dp
),
suspicious_windows AS (
    SELECT
        rs.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city
    FROM rolling_stats rs
    JOIN cus c ON c.h01 = rs.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty cty ON cty.d01 = a.e05
    JOIN cnt cnt ON cnt.c01 = cty.d03
    WHERE rs.window_amount_7d >= 3.0 * rs.hist_avg_amount_30d
      AND rs.window_count_7d >= 5
      AND rs.hist_avg_amount_30d IS NOT NULL
)
SELECT
    sw.payment_date,
    sw.customer_name,
    sw.country,
    sw.city,
    sw.window_amount_7d,
    sw.window_count_7d,
    sw.staff_ids,
    sw.store_ids,
    sw.film_count,
    RANK() OVER (ORDER BY sw.window_amount_7d DESC) AS global_suspicious_rank
FROM suspicious_windows sw
ORDER BY sw.window_amount_7d DESC;