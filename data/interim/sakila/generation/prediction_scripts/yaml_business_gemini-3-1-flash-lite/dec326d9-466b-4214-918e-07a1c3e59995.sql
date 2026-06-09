WITH daily_activity AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS activity_date,
        SUM(p.p05) AS daily_amount,
        COUNT(*) AS daily_count,
        COUNT(DISTINCT p.p03) AS daily_staff_count,
        COUNT(DISTINCT st.o07) AS daily_store_count,
        COUNT(DISTINCT r.q03) AS daily_films_count
    FROM pay p
    JOIN stf st ON st.o01 = p.p03
    JOIN ren r ON r.q01 = p.p04
    GROUP BY p.p02, DATE(p.p06)
),
window_activity AS (
    SELECT
        da.customer_id,
        da.activity_date AS window_end,
        SUM(da.daily_amount) OVER (PARTITION BY da.customer_id ORDER BY JULIANDAY(da.activity_date) RANGE BETWEEN 6 PRECEDING AND CURRENT ROW) AS window_amount,
        SUM(da.daily_count) OVER (PARTITION BY da.customer_id ORDER BY JULIANDAY(da.activity_date) RANGE BETWEEN 6 PRECEDING AND CURRENT ROW) AS window_count,
        SUM(da.daily_films_count) OVER (PARTITION BY da.customer_id ORDER BY JULIANDAY(da.activity_date) RANGE BETWEEN 6 PRECEDING AND CURRENT ROW) AS window_films_count,
        (SELECT AVG(sub.daily_amount) FROM daily_activity sub WHERE sub.customer_id = da.customer_id AND sub.activity_date >= DATE(da.activity_date, '-30 days') AND sub.activity_date < da.activity_date) AS hist_avg_amount
    FROM daily_activity da
),
suspicious_windows AS (
    SELECT
        wa.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city
    FROM window_activity wa
    JOIN cus c ON c.h01 = wa.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty cty ON cty.d01 = a.e05
    JOIN cnt cnt ON cnt.c01 = cty.d03
    WHERE wa.window_amount >= 3 * COALESCE(wa.hist_avg_amount, 0)
      AND wa.window_count >= 5
      AND wa.hist_avg_amount > 0
),
ranked_suspicious AS (
    SELECT
        *,
        RANK() OVER (ORDER BY window_amount DESC) AS global_rank
    FROM suspicious_windows
)
SELECT
    customer_name,
    country,
    city,
    window_end,
    window_amount,
    window_count,
    window_films_count,
    global_rank
FROM ranked_suspicious
ORDER BY global_rank;