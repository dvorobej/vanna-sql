WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(p.p05) AS daily_sum,
        COUNT(*) AS daily_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT CASE WHEN st.o07 <> cu.h02 THEN p.p03 END) AS foreign_staff_count,
        CAST(COUNT(DISTINCT CASE WHEN st.o07 <> cu.h02 THEN p.p03 END) AS REAL) / NULLIF(COUNT(DISTINCT p.p03), 0) AS foreign_staff_ratio
    FROM pay p
    JOIN cus cu ON cu.h01 = p.p02
    JOIN stf st ON st.o01 = p.p03
    GROUP BY p.p02, date(p.p06)
),
history_stats AS (
    SELECT
        ds.*,
        AVG(ds.daily_sum) OVER (PARTITION BY ds.customer_id ORDER BY ds.payment_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) AS avg_sum_30d,
        (SELECT AVG(val * val) FROM (SELECT ds2.daily_sum AS val FROM daily_stats ds2 WHERE ds2.customer_id = ds.customer_id AND ds2.payment_date >= date(ds.payment_date, '-30 days') AND ds2.payment_date < ds.payment_date)) - (AVG(ds.daily_sum) OVER (PARTITION BY ds.customer_id ORDER BY ds.payment_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) * AVG(ds.daily_sum) OVER (PARTITION BY ds.customer_id ORDER BY ds.payment_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING)) AS var_sum_30d,
        AVG(ds.daily_count) OVER (PARTITION BY ds.customer_id ORDER BY ds.payment_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) AS avg_count_30d
    FROM daily_stats ds
),
suspicious_days AS (
    SELECT
        *,
        SQRT(ABS(var_sum_30d)) AS stddev_sum_30d
    FROM history_stats
    WHERE avg_sum_30d IS NOT NULL
      AND (daily_sum > avg_sum_30d + 3 * SQRT(ABS(var_sum_30d)) OR daily_count > avg_count_30d * 3)
),
top_staff_and_cat AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        (SELECT o02 || ' ' || o03 FROM stf WHERE o01 = p.p03 GROUP BY p.p03 ORDER BY COUNT(*) DESC LIMIT 1) AS top_staff,
        (SELECT ca.g02 FROM ren r JOIN inv i ON i.n01 = r.q03 JOIN flc fc ON fc.l01 = i.n02 JOIN cat ca ON ca.g01 = fc.l02 WHERE r.q01 = p.p04 GROUP BY ca.g02 ORDER BY COUNT(*) DESC LIMIT 1) AS top_category
    FROM pay p
    GROUP BY p.p02, date(p.p06)
)
SELECT
    sd.customer_id,
    cu.h03 || ' ' || cu.h04 AS customer_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    sd.payment_date,
    sd.daily_sum,
    sd.daily_count,
    sd.foreign_staff_ratio,
    ts.top_staff,
    ts.top_category,
    RANK() OVER (ORDER BY (sd.daily_sum / NULLIF(sd.avg_sum_30d, 0)) DESC) AS suspicion_rank
FROM suspicious_days sd
JOIN cus cu ON cu.h01 = sd.customer_id
JOIN adr ON adr.e01 = cu.h06
JOIN cty ON cty.d01 = adr.e05
JOIN cnt ON cnt.c01 = cty.d03
JOIN top_staff_and_cat ts ON ts.customer_id = sd.customer_id AND ts.payment_date = sd.payment_date
ORDER BY suspicion_rank;