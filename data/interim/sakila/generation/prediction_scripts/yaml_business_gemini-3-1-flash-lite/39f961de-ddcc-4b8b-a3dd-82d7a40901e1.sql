WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(p.p05) AS day_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        SUM(CASE WHEN f.i11 IN ('R', 'NC-17') THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS share_r_nc17
    FROM pay p
    JOIN stf s ON p.p03 = s.o01
    JOIN ren r ON p.p04 = r.q01
    JOIN inv i ON r.q03 = i.n01
    JOIN flm f ON i.n02 = f.i01
    GROUP BY p.p02, date(p.p06)
),
history_stats AS (
    SELECT
        ds.*,
        (
            SELECT AVG(ds2.day_amount)
            FROM daily_stats ds2
            WHERE ds2.customer_id = ds.customer_id
              AND ds2.payment_date >= date(ds.payment_date, '-30 days')
              AND ds2.payment_date < ds.payment_date
        ) AS avg_prev_30
    FROM daily_stats ds
),
suspicious_days AS (
    SELECT
        hs.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        cnt.c01 AS country_id
    FROM history_stats hs
    JOIN cus c ON hs.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty cty ON a.e05 = cty.d01
    JOIN cnt cnt ON cty.d03 = cnt.c01
    WHERE hs.avg_prev_30 > 0
      AND hs.day_amount >= 3 * hs.avg_prev_30
      AND (hs.staff_count > 1 OR hs.store_count > 1)
)
SELECT
    customer_name,
    country,
    city,
    payment_date,
    payment_count,
    ROUND(day_amount, 2) AS day_amount,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(share_r_nc17, 4) AS share_r_nc17,
    RANK() OVER (PARTITION BY country_id, payment_date ORDER BY day_amount DESC) AS country_day_rank
FROM suspicious_days
ORDER BY country, payment_date, country_day_rank;