WITH daily_activity AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS activity_date,
        SUM(p.p05) AS daily_amount,
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
        da.*,
        (
            SELECT AVG(da2.daily_amount)
            FROM daily_activity da2
            WHERE da2.customer_id = da.customer_id
              AND da2.activity_date >= date(da.activity_date, '-30 days')
              AND da2.activity_date < da.activity_date
        ) AS avg_prev_30_days
    FROM daily_activity da
    WHERE da.staff_count > 1 OR da.store_count > 1
),
suspicious_days AS (
    SELECT
        hs.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cty.d02 AS city,
        cnt.c02 AS country,
        cnt.c01 AS country_id,
        RANK() OVER (PARTITION BY cnt.c01, hs.activity_date ORDER BY hs.daily_amount DESC) AS country_rank
    FROM history_stats hs
    JOIN cus c ON hs.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ON a.e05 = cty.d01
    JOIN cnt ON cty.d03 = cnt.c01
    WHERE hs.avg_prev_30_days IS NOT NULL
      AND hs.daily_amount > 3 * hs.avg_prev_30_days
)
SELECT
    customer_name,
    country,
    city,
    activity_date,
    payment_count,
    ROUND(daily_amount, 2) AS daily_amount,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(share_r_nc17, 4) AS share_r_nc17,
    country_rank
FROM suspicious_days
ORDER BY country, activity_date, country_rank;