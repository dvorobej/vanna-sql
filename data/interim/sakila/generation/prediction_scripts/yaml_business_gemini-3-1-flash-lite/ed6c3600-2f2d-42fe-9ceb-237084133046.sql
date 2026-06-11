WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(p.p05) AS daily_sum,
        COUNT(*) AS daily_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT CASE WHEN st.o07 != c.h02 THEN p.p03 END) AS foreign_staff_count
    FROM pay p
    JOIN cus c ON c.h01 = p.p02
    JOIN stf st ON st.o01 = p.p03
    GROUP BY p.p02, date(p.p06)
),
history_stats AS (
    SELECT
        ds.*,
        AVG(ds.daily_sum) OVER (PARTITION BY ds.customer_id ORDER BY ds.payment_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) AS avg_sum_30d,
        AVG(ds.daily_count) OVER (PARTITION BY ds.customer_id ORDER BY ds.payment_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) AS avg_count_30d,
        (SELECT AVG(sq.daily_sum * sq.daily_sum) - AVG(sq.daily_sum) * AVG(sq.daily_sum) 
         FROM daily_stats sq WHERE sq.customer_id = ds.customer_id AND sq.payment_date < ds.payment_date) AS var_sum_30d
    FROM daily_stats ds
),
suspicious_days AS (
    SELECT
        hs.*,
        SQRT(ABS(hs.var_sum_30d)) AS stddev_sum_30d,
        (hs.daily_sum - hs.avg_sum_30d) / NULLIF(SQRT(ABS(hs.var_sum_30d)), 0) AS z_score_sum
    FROM history_stats hs
    WHERE hs.avg_sum_30d IS NOT NULL
      AND (hs.daily_sum > hs.avg_sum_30d + 3 * SQRT(ABS(hs.var_sum_30d)) OR hs.daily_count > hs.avg_count_30d * 3)
),
top_staff_cat AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        (SELECT p2.p03 FROM pay p2 WHERE p2.p02 = p.p02 AND date(p2.p06) = date(p.p06) GROUP BY p2.p03 ORDER BY COUNT(*) DESC LIMIT 1) AS top_staff_id,
        (SELECT cat.g02 FROM pay p2 JOIN ren r ON r.q01 = p2.p04 JOIN inv i ON i.n01 = r.q03 JOIN flc fc ON fc.l01 = i.n02 JOIN cat ON cat.g01 = fc.l02 WHERE p2.p02 = p.p02 AND date(p2.p06) = date(p.p06) GROUP BY cat.g02 ORDER BY COUNT(*) DESC LIMIT 1) AS top_category
    FROM pay p
    GROUP BY p.p02, date(p.p06)
)
SELECT
    sd.customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    sd.payment_date,
    sd.daily_sum,
    sd.daily_count,
    ROUND(sd.foreign_staff_count * 1.0 / NULLIF(sd.daily_count, 0), 2) AS foreign_staff_ratio,
    tsc.top_staff_id,
    tsc.top_category,
    RANK() OVER (ORDER BY sd.z_score_sum DESC) AS suspicion_rank
FROM suspicious_days sd
JOIN cus c ON c.h01 = sd.customer_id
JOIN adr ON adr.e01 = c.h06
JOIN cty ON cty.d01 = adr.e05
JOIN cnt ON cnt.c01 = cty.d03
JOIN top_staff_cat tsc ON tsc.customer_id = sd.customer_id AND tsc.payment_date = sd.payment_date
ORDER BY suspicion_rank;