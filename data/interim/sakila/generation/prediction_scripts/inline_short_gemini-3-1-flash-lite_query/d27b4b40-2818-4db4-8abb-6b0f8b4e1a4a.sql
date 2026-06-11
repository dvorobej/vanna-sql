WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(p.p05) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, date(p.p06)
),
history_stats AS (
    SELECT
        ds.*,
        (
            SELECT AVG(h.day_amount)
            FROM daily_stats AS h
            WHERE h.customer_id = ds.customer_id
              AND h.payment_date >= date(ds.payment_date, '-30 days')
              AND h.payment_date < ds.payment_date
        ) AS avg_prev_30d
    FROM daily_stats AS ds
),
suspicious_days AS (
    SELECT
        hs.*,
        (hs.day_amount / NULLIF(hs.avg_prev_30d, 0)) AS excess_ratio,
        RANK() OVER (
            PARTITION BY hs.customer_id
            ORDER BY hs.day_amount DESC
        ) AS day_rank_for_customer
    FROM history_stats AS hs
    WHERE hs.avg_prev_30d > 0
      AND hs.day_amount >= 3 * hs.avg_prev_30d
      AND hs.payment_count >= 3
      AND (hs.staff_count > 1 OR hs.store_count > 1)
)
SELECT
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    sd.payment_date,
    sd.payment_count,
    ROUND(sd.day_amount, 2) AS total_amount,
    ROUND(sd.avg_prev_30d, 2) AS avg_prev_30d,
    ROUND(sd.excess_ratio, 2) AS excess_ratio,
    sd.day_rank_for_customer
FROM suspicious_days AS sd
JOIN cus AS c ON c.h01 = sd.customer_id
JOIN adr AS a ON a.e01 = c.h06
JOIN cty ON cty.d01 = a.e05
JOIN cnt ON cnt.c01 = cty.d03
ORDER BY sd.day_amount DESC;