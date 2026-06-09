WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS p_date,
        SUM(p.p05) AS daily_sum,
        COUNT(*) AS daily_count
    FROM pay p
    GROUP BY p.p02, date(p.p06)
),
history_stats AS (
    SELECT
        ds.customer_id,
        ds.p_date,
        ds.daily_sum,
        ds.daily_count,
        AVG(ds.daily_sum) OVER (PARTITION BY ds.customer_id ORDER BY ds.p_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) AS avg_sum_30d,
        (SELECT AVG(val * val) FROM (SELECT ds2.daily_sum AS val FROM daily_stats ds2 WHERE ds2.customer_id = ds.customer_id AND ds2.p_date < ds.p_date ORDER BY ds2.p_date DESC LIMIT 30)) - (AVG(ds.daily_sum) OVER (PARTITION BY ds.customer_id ORDER BY ds.p_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) * AVG(ds.daily_sum) OVER (PARTITION BY ds.customer_id ORDER BY ds.p_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING)) AS var_sum_30d,
        COUNT(*) OVER (PARTITION BY ds.customer_id ORDER BY ds.p_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) AS hist_count
    FROM daily_stats ds
),
anomalies AS (
    SELECT *,
        SQRT(ABS(var_sum_30d)) AS std_sum_30d
    FROM history_stats
    WHERE hist_count >= 10
      AND (daily_sum > avg_sum_30d + 3 * SQRT(ABS(var_sum_30d)) OR daily_count > 10)
),
details AS (
    SELECT
        a.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        (SELECT COUNT(*) FROM pay p2 JOIN stf s ON p2.p03 = s.o01 WHERE p2.p02 = a.customer_id AND date(p2.p06) = a.p_date AND s.o07 <> c.h02) * 1.0 / a.daily_count AS off_store_share,
        (SELECT s.o02 || ' ' || s.o03 FROM pay p2 JOIN stf s ON p2.p03 = s.o01 WHERE p2.p02 = a.customer_id AND date(p2.p06) = a.p_date GROUP BY p2.p03 ORDER BY COUNT(*) DESC LIMIT 1) AS top_staff,
        (SELECT cat.g02 FROM pay p2 JOIN ren r ON p2.p04 = r.q01 JOIN inv i ON r.q03 = i.n01 JOIN flc fc ON i.n02 = fc.l01 JOIN cat ON fc.l02 = cat.g01 WHERE p2.p02 = a.customer_id AND date(p2.p06) = a.p_date GROUP BY cat.g02 ORDER BY COUNT(*) DESC LIMIT 1) AS top_category
    FROM anomalies a
    JOIN cus c ON a.customer_id = c.h01
    JOIN adr ON c.h06 = adr.e01
    JOIN cty ON adr.e05 = cty.d01
    JOIN cnt ON cty.d03 = cnt.c01
)
SELECT *,
    RANK() OVER (ORDER BY (daily_sum / NULLIF(avg_sum_30d, 0)) * daily_count DESC) AS risk_rank
FROM details
ORDER BY risk_rank;