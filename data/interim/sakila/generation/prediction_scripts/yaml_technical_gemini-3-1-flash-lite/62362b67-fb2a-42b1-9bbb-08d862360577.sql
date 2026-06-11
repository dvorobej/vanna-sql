WITH daily_activity AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS activity_date,
        SUM(CAST(p.p05 AS REAL)) AS daily_amount,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT inv.n03) AS store_count
    FROM pay AS p
    LEFT JOIN ren AS r ON r.q01 = p.p04
    LEFT JOIN inv ON inv.n01 = r.q03
    GROUP BY p.p02, DATE(p.p06)
),
daily_with_history AS (
    SELECT
        da.*,
        (
            SELECT AVG(prev.daily_amount)
            FROM daily_activity AS prev
            WHERE prev.customer_id = da.customer_id
              AND prev.activity_date >= DATE(da.activity_date, '-30 days')
              AND prev.activity_date < da.activity_date
        ) AS avg_prev_30d
    FROM daily_activity AS da
),
suspicious_days AS (
    SELECT
        dwh.*,
        (dwh.daily_amount / NULLIF(dwh.avg_prev_30d, 0)) AS exceed_ratio
    FROM daily_with_history AS dwh
    WHERE dwh.avg_prev_30d > 0
      AND dwh.daily_amount >= 3 * dwh.avg_prev_30d
      AND (dwh.staff_count > 1 OR dwh.store_count > 1)
)
SELECT
    sd.customer_id,
    cnt.c02 AS country,
    cty.d02 AS city,
    sd.activity_date,
    ROUND(sd.daily_amount, 2) AS daily_amount,
    sd.payment_count,
    sd.staff_count,
    ROUND(sd.avg_prev_30d, 2) AS avg_prev_30d,
    RANK() OVER (ORDER BY sd.exceed_ratio DESC) AS global_exceed_rank
FROM suspicious_days AS sd
JOIN cus ON cus.h01 = sd.customer_id
JOIN adr ON adr.e01 = cus.h06
JOIN cty ON cty.d01 = adr.e05
JOIN cnt ON cnt.c01 = cty.d03
ORDER BY global_exceed_rank;