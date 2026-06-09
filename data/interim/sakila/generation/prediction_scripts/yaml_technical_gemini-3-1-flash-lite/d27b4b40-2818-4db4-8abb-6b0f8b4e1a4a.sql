WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(p.p01) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS daily_sum,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT i.n03) AS store_count
    FROM pay AS p
    LEFT JOIN ren AS r ON r.q01 = p.p04
    LEFT JOIN inv AS i ON i.n01 = r.q03
    GROUP BY p.p02, date(p.p06)
),
history_stats AS (
    SELECT
        ds.*,
        (
            SELECT AVG(prev.daily_sum)
            FROM daily_stats AS prev
            WHERE prev.customer_id = ds.customer_id
              AND prev.payment_date >= date(ds.payment_date, '-30 days')
              AND prev.payment_date < ds.payment_date
        ) AS avg_prev_30
    FROM daily_stats AS ds
    WHERE ds.payment_count >= 3
      AND (ds.staff_count > 1 OR ds.store_count > 1)
),
suspicious_days AS (
    SELECT
        hs.*,
        (hs.daily_sum / hs.avg_prev_30) AS excess_ratio,
        RANK() OVER (PARTITION BY hs.customer_id ORDER BY hs.daily_sum DESC) AS day_rank
    FROM history_stats AS hs
    WHERE hs.avg_prev_30 > 0
      AND hs.daily_sum >= 3 * hs.avg_prev_30
)
SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    sd.payment_date,
    sd.payment_count,
    ROUND(sd.daily_sum, 2) AS daily_sum,
    ROUND(sd.avg_prev_30, 2) AS avg_prev_30,
    ROUND(sd.excess_ratio, 2) AS excess_ratio,
    sd.day_rank
FROM suspicious_days AS sd
JOIN cus AS c ON c.h01 = sd.customer_id
JOIN adr ON adr.e01 = c.h06
JOIN cty ON cty.d01 = adr.e05
JOIN cnt ON cnt.c01 = cty.d03
ORDER BY sd.daily_sum DESC, sd.customer_id, sd.payment_date;