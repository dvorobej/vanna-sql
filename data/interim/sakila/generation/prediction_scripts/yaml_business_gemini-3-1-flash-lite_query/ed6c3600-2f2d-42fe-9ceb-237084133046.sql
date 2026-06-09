WITH daily_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS p_date,
        SUM(p.p05) AS daily_sum,
        COUNT(*) AS daily_count,
        GROUP_CONCAT(p.p03) AS staff_list,
        COUNT(DISTINCT CASE WHEN s.o07 <> c.h02 THEN p.p03 END) * 1.0 / COUNT(*) AS off_home_store_share
    FROM pay p
    JOIN cus c ON c.h01 = p.p02
    JOIN stf s ON s.o01 = p.p03
    GROUP BY p.p02, date(p.p06)
),
history_stats AS (
    SELECT
        dcs.*,
        AVG(dcs.daily_sum) OVER (PARTITION BY dcs.customer_id ORDER BY dcs.p_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) AS avg_sum_30d,
        (SELECT AVG(val * val) FROM (SELECT daily_sum AS val FROM daily_customer_stats d2 WHERE d2.customer_id = dcs.customer_id AND d2.p_date < dcs.p_date ORDER BY d2.p_date DESC LIMIT 30)) - (AVG(dcs.daily_sum) OVER (PARTITION BY dcs.customer_id ORDER BY dcs.p_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) * AVG(dcs.daily_sum) OVER (PARTITION BY dcs.customer_id ORDER BY dcs.p_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING)) AS var_sum_30d,
        COUNT(*) OVER (PARTITION BY dcs.customer_id ORDER BY dcs.p_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) AS hist_count
    FROM daily_customer_stats dcs
),
anomalies AS (
    SELECT
        hs.*,
        (daily_sum - avg_sum_30d) / NULLIF(SQRT(ABS(var_sum_30d)), 0) AS z_score
    FROM history_stats hs
    WHERE hist_count >= 10
),
top_staff_and_cat AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS p_date,
        (SELECT p3.p03 FROM pay p3 WHERE p3.p02 = p.p02 AND date(p3.p06) = date(p.p06) GROUP BY p3.p03 ORDER BY COUNT(*) DESC LIMIT 1) AS top_staff_id,
        (SELECT cat.g02 FROM ren r JOIN inv i ON i.n01 = r.q03 JOIN flc fc ON fc.l01 = i.n02 JOIN cat ON cat.g01 = fc.l02 WHERE r.q04 = p.p02 AND date(r.q02) = date(p.p06) GROUP BY cat.g02 ORDER BY COUNT(*) DESC LIMIT 1) AS top_category
    FROM pay p
    GROUP BY p.p02, date(p.p06)
)
SELECT
    a.customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    a.p_date,
    a.daily_sum,
    a.daily_count,
    a.off_home_store_share,
    ts.top_staff_id,
    ts.top_category,
    RANK() OVER (ORDER BY a.z_score DESC, a.daily_count DESC) AS risk_rank
FROM anomalies a
JOIN cus c ON c.h01 = a.customer_id
JOIN adr ON adr.e01 = c.h06
JOIN cty ON cty.d01 = adr.e05
JOIN cnt ON cnt.c01 = cty.d03
JOIN top_staff_and_cat ts ON ts.customer_id = a.customer_id AND ts.p_date = a.p_date
WHERE a.z_score > 3 OR a.daily_count > 10
ORDER BY risk_rank ASC;