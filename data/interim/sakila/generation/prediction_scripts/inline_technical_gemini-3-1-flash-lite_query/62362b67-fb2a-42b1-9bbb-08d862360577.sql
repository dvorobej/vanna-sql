WITH daily_activity AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        SUM(p.p05) AS daily_sum,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, DATE(p.p06)
),
history_stats AS (
    SELECT
        da.customer_id,
        da.payment_date,
        da.daily_sum,
        da.payment_count,
        da.staff_count,
        da.store_count,
        (
            SELECT AVG(h.daily_sum)
            FROM daily_activity AS h
            WHERE h.customer_id = da.customer_id
              AND h.payment_date >= DATE(da.payment_date, '-30 days')
              AND h.payment_date < da.payment_date
        ) AS avg_prev_30d
    FROM daily_activity AS da
    WHERE (da.staff_count > 1 OR da.store_count > 1)
),
suspicious_cases AS (
    SELECT
        hs.*,
        (hs.daily_sum / NULLIF(hs.avg_prev_30d, 0)) AS excess_ratio
    FROM history_stats AS hs
    WHERE hs.avg_prev_30d IS NOT NULL
      AND hs.daily_sum >= 3.0 * hs.avg_prev_30d
)
SELECT
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    sc.payment_date,
    sc.daily_sum,
    sc.payment_count,
    sc.staff_count,
    ROUND(sc.avg_prev_30d, 2) AS avg_prev_30d,
    RANK() OVER (ORDER BY sc.excess_ratio DESC) AS suspicion_rank
FROM suspicious_cases AS sc
JOIN cus AS c ON c.h01 = sc.customer_id
JOIN adr AS a ON a.e01 = c.h06
JOIN cty ON cty.d01 = a.e05
JOIN cnt ON cnt.c01 = cty.d03
ORDER BY suspicion_rank;