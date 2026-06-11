WITH daily_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        COUNT(*) AS daily_count,
        SUM(p.p05) AS daily_amount,
        GROUP_CONCAT(DISTINCT p.p03) AS staff_ids,
        GROUP_CONCAT(DISTINCT st.o07) AS store_ids,
        COUNT(DISTINCT r.q03) AS distinct_films_count
    FROM pay p
    JOIN stf st ON st.o01 = p.p03
    LEFT JOIN ren r ON r.q01 = p.p04
    GROUP BY p.p02, DATE(p.p06)
),
rolling_stats AS (
    SELECT
        dcs.*,
        SUM(dcs.daily_amount) OVER (
            PARTITION BY dcs.customer_id 
            ORDER BY JULIANDAY(dcs.payment_date) 
            RANGE BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS window_amount_7d,
        SUM(dcs.daily_count) OVER (
            PARTITION BY dcs.customer_id 
            ORDER BY JULIANDAY(dcs.payment_date) 
            RANGE BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS window_count_7d,
        AVG(dcs.daily_amount) OVER (
            PARTITION BY dcs.customer_id 
            ORDER BY JULIANDAY(dcs.payment_date) 
            RANGE BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS hist_avg_amount_30d,
        COUNT(*) OVER (
            PARTITION BY dcs.customer_id 
            ORDER BY JULIANDAY(dcs.payment_date) 
            RANGE BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS hist_days_count_30d
    FROM daily_customer_stats dcs
),
suspicious_events AS (
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
    WHERE rs.hist_days_count_30d > 0
      AND rs.window_amount_7d >= 3.0 * rs.hist_avg_amount_30d
      AND rs.window_count_7d >= 5
),
ranked_suspicious AS (
    SELECT
        *,
        RANK() OVER (ORDER BY window_amount_7d DESC) AS global_suspicious_rank
    FROM suspicious_events
)
SELECT
    payment_date,
    customer_name,
    country,
    city,
    window_amount_7d,
    window_count_7d,
    staff_ids,
    store_ids,
    distinct_films_count,
    global_suspicious_rank
FROM ranked_suspicious
ORDER BY global_suspicious_rank;