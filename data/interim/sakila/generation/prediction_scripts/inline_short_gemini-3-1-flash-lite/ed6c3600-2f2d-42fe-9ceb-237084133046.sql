WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(p.p01) AS daily_payment_count,
        SUM(p.p05) AS daily_total_amount,
        AVG(p.p05) AS daily_avg_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT r.q03) AS film_count
    FROM pay AS p
    LEFT JOIN ren AS r ON p.p04 = r.q01
    GROUP BY p.p02, date(p.p06)
),
moving_stats AS (
    SELECT
        *,
        AVG(daily_total_amount) OVER (
            PARTITION BY customer_id 
            ORDER BY payment_date 
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS avg_30d_amount,
        STDEV(daily_total_amount) OVER (
            PARTITION BY customer_id 
            ORDER BY payment_date 
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS stddev_30d_amount
    FROM daily_stats
),
anomaly_scoring AS (
    SELECT
        *,
        (daily_total_amount - avg_30d_amount) / NULLIF(stddev_30d_amount, 0) AS z_score,
        CASE 
            WHEN daily_payment_count > 10 THEN 3
            WHEN daily_total_amount > (avg_30d_amount * 3) THEN 2
            WHEN staff_count > 3 THEN 1
            ELSE 0
        END AS risk_level
    FROM moving_stats
    WHERE avg_30d_amount IS NOT NULL
)
SELECT
    c.h03 || ' ' || c.h04 AS customer_name,
    a.payment_date,
    a.daily_payment_count,
    ROUND(a.daily_total_amount, 2) AS daily_total_amount,
    ROUND(a.avg_30d_amount, 2) AS avg_30d_amount,
    ROUND(a.z_score, 2) AS z_score,
    a.risk_level,
    RANK() OVER (ORDER BY a.risk_level DESC, a.z_score DESC) AS suspicion_rank
FROM anomaly_scoring AS a
JOIN cus AS c ON a.customer_id = c.h01
WHERE a.risk_level > 0 OR a.z_score > 3
ORDER BY suspicion_rank ASC;