WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS p_date,
        SUM(p.p05) AS daily_sum,
        COUNT(*) AS daily_count
    FROM pay p
    GROUP BY p.p02, date(p.p06)
),
rolling_stats AS (
    SELECT
        ds.*,
        AVG(ds.daily_sum) OVER (PARTITION BY ds.customer_id ORDER BY ds.p_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) AS avg_sum_30d,
        (SELECT AVG(val) FROM (SELECT ds2.daily_sum AS val FROM daily_stats ds2 WHERE ds2.customer_id = ds.customer_id AND ds2.p_date < ds.p_date ORDER BY ds2.p_date DESC LIMIT 30)) AS avg_sum,
        (SELECT AVG(val*val) - AVG(val)*AVG(val) FROM (SELECT ds2.daily_sum AS val FROM daily_stats ds2 WHERE ds2.customer_id = ds.customer_id AND ds2.p_date < ds.p_date ORDER BY ds2.p_date DESC LIMIT 30)) AS var_sum,
        COUNT(*) OVER (PARTITION BY ds.customer_id ORDER BY ds.p_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) AS hist_count
    FROM daily_stats ds
),
anomalies AS (
    SELECT
        rs.*,
        SQRT(ABS(rs.var_sum)) AS std_sum
    FROM rolling_stats rs
    WHERE rs.hist_count >= 10
      AND (rs.daily_sum > rs.avg_sum_30d + 3 * SQRT(ABS(rs.var_sum)) OR rs.daily_count > 5)
),
customer_details AS (
    SELECT
        a.customer_id,
        a.p_date,
        a.daily_sum,
        a.daily_count,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        (SELECT stf.o02 || ' ' || stf.o03 FROM pay p2 JOIN stf ON stf.o01 = p2.p03 WHERE p2.p02 = a.customer_id AND date(p2.p06) = a.p_date GROUP BY p2.p03 ORDER BY COUNT(*) DESC LIMIT 1) AS top_staff,
        (SELECT cat.g02 FROM pay p3 JOIN ren r ON r.q01 = p3.p04 JOIN inv i ON i.n01 = r.q03 JOIN flc ON flc.l01 = i.n02 JOIN cat ON cat.g01 = flc.l02 WHERE p3.p02 = a.customer_id AND date(p3.p06) = a.p_date GROUP BY cat.g02 ORDER BY COUNT(*) DESC LIMIT 1) AS top_category,
        (CAST(SUM(CASE WHEN stf.o07 <> c.h02 THEN 1 ELSE 0 END) AS REAL) / COUNT(*)) AS off_store_share
    FROM anomalies a
    JOIN cus c ON c.h01 = a.customer_id
    JOIN adr ON adr.e01 = c.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
    JOIN pay p ON p.p02 = a.customer_id AND date(p.p06) = a.p_date
    JOIN stf ON stf.o01 = p.p03
    GROUP BY a.customer_id, a.p_date
)
SELECT
    *,
    DENSE_RANK() OVER (ORDER BY (daily_sum / NULLIF(avg_sum_30d, 0)) * daily_count DESC) AS risk_rank
FROM customer_details
ORDER BY risk_rank ASC;