WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS p_date,
        SUM(p.p05) AS daily_sum,
        COUNT(*) AS daily_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        SUM(CASE WHEN st.o07 <> cu.h02 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS off_home_store_share
    FROM pay p
    JOIN cus cu ON cu.h01 = p.p02
    JOIN stf st ON st.o01 = p.p03
    GROUP BY p.p02, date(p.p06)
),
history_stats AS (
    SELECT
        ds.*,
        AVG(ds.daily_sum) OVER (PARTITION BY ds.customer_id ORDER BY ds.p_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) AS avg_sum_30d,
        (SELECT AVG(val) FROM (SELECT ds2.daily_sum AS val FROM daily_stats ds2 WHERE ds2.customer_id = ds.customer_id AND ds2.p_date < ds.p_date ORDER BY ds2.p_date DESC LIMIT 30)) AS avg_sum,
        (SELECT AVG(val*val) - AVG(val)*AVG(val) FROM (SELECT ds2.daily_sum AS val FROM daily_stats ds2 WHERE ds2.customer_id = ds.customer_id AND ds2.p_date < ds.p_date ORDER BY ds2.p_date DESC LIMIT 30)) AS var_sum_30d
    FROM daily_stats ds
),
anomalies AS (
    SELECT
        hs.*,
        SQRT(ABS(hs.var_sum_30d)) AS std_sum_30d
    FROM history_stats hs
    WHERE hs.avg_sum_30d IS NOT NULL
      AND (hs.daily_sum > hs.avg_sum_30d + 3 * SQRT(ABS(hs.var_sum_30d)) OR hs.daily_count > 10)
),
top_staff_cat AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS p_date,
        (SELECT p2.p03 FROM pay p2 WHERE p2.p02 = p.p02 AND date(p2.p06) = date(p.p06) GROUP BY p2.p03 ORDER BY COUNT(*) DESC LIMIT 1) AS top_staff_id,
        (SELECT ca.g02 FROM pay p2 JOIN ren r ON r.q01 = p2.p04 JOIN inv i ON i.n01 = r.q03 JOIN flc fc ON fc.l01 = i.n02 JOIN cat ca ON ca.g01 = fc.l02 WHERE p2.p02 = p.p02 AND date(p2.p06) = date(p.p06) GROUP BY ca.g02 ORDER BY COUNT(*) DESC LIMIT 1) AS top_cat
    FROM pay p
    GROUP BY p.p02, date(p.p06)
)
SELECT
    a.p_date,
    a.customer_id,
    cu.h03 || ' ' || cu.h04 AS customer_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    a.daily_sum,
    a.daily_count,
    a.off_home_store_share,
    tsc.top_staff_id,
    tsc.top_cat,
    RANK() OVER (ORDER BY (a.daily_sum / NULLIF(a.avg_sum_30d, 0)) DESC) AS risk_rank
FROM anomalies a
JOIN cus cu ON cu.h01 = a.customer_id
JOIN adr ON adr.e01 = cu.h06
JOIN cty ON cty.d01 = adr.e05
JOIN cnt ON cnt.c01 = cty.d03
JOIN top_staff_cat tsc ON tsc.customer_id = a.customer_id AND tsc.p_date = a.p_date
ORDER BY risk_rank ASC;