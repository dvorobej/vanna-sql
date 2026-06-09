WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(p.p01) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS daily_sum,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT i.n03) AS store_count
    FROM pay AS p
    LEFT JOIN ren AS r ON p.p04 = r.q01
    LEFT JOIN inv AS i ON r.q03 = i.n01
    GROUP BY p.p02, date(p.p06)
),
history_stats AS (
    SELECT
        ds.*,
        (
            SELECT AVG(h.daily_sum)
            FROM daily_stats AS h
            WHERE h.customer_id = ds.customer_id
              AND h.payment_date >= date(ds.payment_date, '-30 days')
              AND h.payment_date < ds.payment_date
        ) AS avg_prev_30
    FROM daily_stats AS ds
),
suspicious_days AS (
    SELECT
        hs.*,
        (hs.daily_sum / NULLIF(hs.avg_prev_30, 0)) AS excess_ratio
    FROM history_stats AS hs
    WHERE hs.avg_prev_30 > 0
      AND hs.daily_sum >= 3 * hs.avg_prev_30
      AND hs.payment_count >= 3
      AND (hs.staff_count > 1 OR hs.store_count > 1)
)
SELECT
    sd.customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    sd.payment_date,
    sd.payment_count,
    ROUND(sd.daily_sum, 2) AS daily_sum,
    ROUND(sd.avg_prev_30, 2) AS avg_prev_30,
    ROUND(sd.excess_ratio, 2) AS excess_ratio,
    RANK() OVER (
        PARTITION BY sd.customer_id 
        ORDER BY sd.daily_sum DESC
    ) AS day_rank_for_customer
FROM suspicious_days AS sd
JOIN cus AS c ON sd.customer_id = c.h01
JOIN adr ON c.h06 = adr.e01
JOIN cty ON adr.e05 = cty.d01
JOIN cnt ON cty.d03 = cnt.c01
ORDER BY sd.daily_sum DESC, sd.payment_date;