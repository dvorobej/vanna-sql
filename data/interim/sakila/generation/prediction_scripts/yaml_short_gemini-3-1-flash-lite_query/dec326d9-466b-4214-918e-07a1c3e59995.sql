WITH daily_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        COUNT(*) AS daily_count,
        SUM(p.p05) AS daily_amount,
        COUNT(DISTINCT r.q03) AS daily_films_count,
        GROUP_CONCAT(DISTINCT p.p03) AS staff_ids,
        GROUP_CONCAT(DISTINCT st.o07) AS store_ids
    FROM pay p
    LEFT JOIN ren r ON p.p04 = r.q01
    LEFT JOIN stf st ON p.p03 = st.o01
    GROUP BY p.p02, DATE(p.p06)
),
rolling_stats AS (
    SELECT
        dcs.*,
        SUM(daily_amount) OVER (
            PARTITION BY customer_id 
            ORDER BY JULIANDAY(payment_date) 
            RANGE BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS rolling_7d_amount,
        SUM(daily_count) OVER (
            PARTITION BY customer_id 
            ORDER BY JULIANDAY(payment_date) 
            RANGE BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS rolling_7d_count,
        SUM(daily_films_count) OVER (
            PARTITION BY customer_id 
            ORDER BY JULIANDAY(payment_date) 
            RANGE BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS rolling_7d_films,
        AVG(daily_amount) OVER (
            PARTITION BY customer_id 
            ORDER BY JULIANDAY(payment_date) 
            RANGE BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS hist_30d_avg_amount
    FROM daily_customer_stats dcs
),
suspicious_events AS (
    SELECT
        rs.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city
    FROM rolling_stats rs
    JOIN cus c ON rs.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ON a.e05 = cty.d01
    JOIN cnt ON cty.d03 = cnt.c01
    WHERE rs.rolling_7d_amount >= 3 * COALESCE(rs.hist_30d_avg_amount, 0)
      AND rs.rolling_7d_count >= 5
      AND rs.hist_30d_avg_amount IS NOT NULL
)
SELECT
    customer_name,
    country,
    city,
    payment_date,
    rolling_7d_amount,
    rolling_7d_count,
    rolling_7d_films,
    staff_ids,
    store_ids,
    RANK() OVER (ORDER BY rolling_7d_amount DESC) AS global_suspicious_rank
FROM suspicious_events
ORDER BY rolling_7d_amount DESC;