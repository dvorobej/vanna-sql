WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(p.p01) AS daily_payment_count,
        SUM(CAST(p.p05 AS REAL)) AS daily_payment_sum,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT i.n03) AS store_count
    FROM pay AS p
    LEFT JOIN ren AS r ON r.q01 = p.p04
    LEFT JOIN inv AS i ON i.n01 = r.q03
    GROUP BY p.p02, date(p.p06)
),
moving_avg AS (
    SELECT
        ds.*,
        AVG(ds.daily_payment_sum) OVER (
            PARTITION BY ds.customer_id 
            ORDER BY ds.payment_date 
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS avg_30d_sum
    FROM daily_stats AS ds
),
risk_scoring AS (
    SELECT
        ma.*,
        (ma.daily_payment_sum / NULLIF(ma.avg_30d_sum, 0)) AS spike_ratio,
        CASE 
            WHEN ma.daily_payment_count >= 5 THEN 3
            WHEN ma.daily_payment_count >= 3 THEN 2
            ELSE 1
        END + 
        CASE 
            WHEN ma.staff_count > 1 OR ma.store_count > 1 THEN 2
            ELSE 0
        END +
        CASE 
            WHEN (ma.daily_payment_sum / NULLIF(ma.avg_30d_sum, 0)) > 5 THEN 3
            WHEN (ma.daily_payment_sum / NULLIF(ma.avg_30d_sum, 0)) > 2 THEN 1
            ELSE 0
        END AS risk_score
    FROM moving_avg AS ma
    WHERE ma.avg_30d_sum > 0
      AND ma.daily_payment_sum > (2 * ma.avg_30d_sum)
)
SELECT
    c.h03 || ' ' || c.h04 AS customer_name,
    rs.payment_date,
    rs.daily_payment_count,
    ROUND(rs.daily_payment_sum, 2) AS daily_payment_sum,
    ROUND(rs.avg_30d_sum, 2) AS avg_30d_sum,
    ROUND(rs.spike_ratio, 2) AS spike_ratio,
    rs.staff_count,
    rs.store_count,
    rs.risk_score,
    RANK() OVER (ORDER BY rs.risk_score DESC, rs.daily_payment_sum DESC) AS global_risk_rank
FROM risk_scoring AS rs
JOIN cus AS c ON c.h01 = rs.customer_id
ORDER BY rs.risk_score DESC, rs.daily_payment_sum DESC;