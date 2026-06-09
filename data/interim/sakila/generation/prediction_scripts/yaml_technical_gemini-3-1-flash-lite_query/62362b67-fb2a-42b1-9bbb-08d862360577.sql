WITH daily_activity AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        SUM(p.p05) AS daily_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, DATE(p.p06)
),
history_stats AS (
    SELECT
        da.*,
        (
            SELECT AVG(da_prev.daily_amount)
            FROM daily_activity AS da_prev
            WHERE da_prev.customer_id = da.customer_id
              AND da_prev.payment_date >= DATE(da.payment_date, '-30 days')
              AND da_prev.payment_date < da.payment_date
        ) AS avg_prev_30d
    FROM daily_activity AS da
),
suspicious_days AS (
    SELECT
        hs.*,
        (hs.daily_amount / NULLIF(hs.avg_prev_30d, 0)) AS excess_ratio
    FROM history_stats AS hs
    WHERE hs.avg_prev_30d > 0
      AND hs.daily_amount >= 3 * hs.avg_prev_30d
      AND (hs.staff_count > 1 OR hs.store_count > 1)
)
SELECT
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    sd.payment_date,
    sd.daily_amount,
    sd.payment_count,
    sd.staff_count,
    ROUND(sd.avg_prev_30d, 2) AS avg_prev_30d,
    RANK() OVER (ORDER BY sd.excess_ratio DESC) AS suspicion_rank
FROM suspicious_days AS sd
JOIN cus AS c ON c.h01 = sd.customer_id
JOIN adr AS a ON a.e01 = c.h06
JOIN cty ON cty.d01 = a.e05
JOIN cnt ON cnt.c01 = cty.d03
ORDER BY suspicion_rank;