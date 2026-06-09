WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(*) AS daily_payment_count,
        SUM(CAST(p.p05 AS REAL)) AS daily_payment_sum,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT i.n03) AS store_count
    FROM pay AS p
    LEFT JOIN ren AS r ON r.q01 = p.p04
    LEFT JOIN inv AS i ON i.n01 = r.q03
    GROUP BY p.p02, date(p.p06)
),
moving_averages AS (
    SELECT
        ds.*,
        AVG(ds.daily_payment_sum) OVER (
            PARTITION BY ds.customer_id 
            ORDER BY ds.payment_date 
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS avg_30d_sum
    FROM daily_stats AS ds
),
suspicious_cases AS (
    SELECT
        ma.*,
        (ma.daily_payment_sum / NULLIF(ma.avg_30d_sum, 0)) AS spike_ratio,
        (ma.daily_payment_count * 0.5 + ma.staff_count * 2 + ma.store_count * 3) AS risk_score
    FROM moving_averages AS ma
    WHERE ma.avg_30d_sum > 0
      AND (ma.daily_payment_sum > 3 * ma.avg_30d_sum OR ma.daily_payment_count > 10)
)
SELECT
    c.h03 || ' ' || c.h04 AS customer_name,
    sc.payment_date,
    sc.daily_payment_count,
    ROUND(sc.daily_payment_sum, 2) AS daily_payment_sum,
    ROUND(sc.avg_30d_sum, 2) AS avg_30d_sum,
    sc.staff_count,
    sc.store_count,
    ROUND(sc.spike_ratio, 2) AS spike_ratio,
    RANK() OVER (ORDER BY sc.risk_score DESC, sc.daily_payment_sum DESC) AS risk_rank
FROM suspicious_cases AS sc
JOIN cus AS c ON c.h01 = sc.customer_id
ORDER BY risk_rank ASC;