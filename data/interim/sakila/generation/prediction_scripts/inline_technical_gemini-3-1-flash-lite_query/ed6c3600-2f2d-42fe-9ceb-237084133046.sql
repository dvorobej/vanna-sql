WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS p_date,
        SUM(p.p05) AS daily_sum,
        COUNT(*) AS daily_count,
        GROUP_CONCAT(p.p03) AS staff_list
    FROM pay p
    GROUP BY p.p02, date(p.p06)
),
rolling_stats AS (
    SELECT
        ds.*,
        AVG(ds.daily_sum) OVER (PARTITION BY ds.customer_id ORDER BY ds.p_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) AS avg_sum_30d,
        (SELECT AVG(val * val) FROM (SELECT ds2.daily_sum AS val FROM daily_stats ds2 WHERE ds2.customer_id = ds.customer_id AND ds2.p_date < ds.p_date ORDER BY ds2.p_date DESC LIMIT 30)) - (AVG(ds.daily_sum) OVER (PARTITION BY ds.customer_id ORDER BY ds.p_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) * AVG(ds.daily_sum) OVER (PARTITION BY ds.customer_id ORDER BY ds.p_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING)) AS var_sum_30d,
        COUNT(*) OVER (PARTITION BY ds.customer_id ORDER BY ds.p_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) AS hist_count
    FROM daily_stats ds
),
suspicious_days AS (
    SELECT
        rs.*,
        SQRT(ABS(rs.var_sum_30d)) AS std_sum_30d
    FROM rolling_stats rs
    WHERE rs.hist_count >= 10
      AND (rs.daily_sum > rs.avg_sum_30d + 3 * SQRT(ABS(rs.var_sum_30d)) OR rs.daily_count > 5)
),
customer_details AS (
    SELECT
        sd.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        (SELECT stf.o01 FROM pay p2 JOIN stf ON stf.o01 = p2.p03 WHERE p2.p02 = sd.customer_id AND date(p2.p06) = sd.p_date GROUP BY p2.p03 ORDER BY COUNT(*) DESC LIMIT 1) AS top_staff_id,
        (SELECT cat.g02 FROM pay p3 JOIN ren r ON r.q01 = p3.p04 JOIN inv i ON i.n01 = r.q03 JOIN flc f ON f.l01 = i.n02 JOIN cat ON cat.g01 = f.l02 WHERE p3.p02 = sd.customer_id AND date(p3.p06) = sd.p_date GROUP BY cat.g02 ORDER BY COUNT(*) DESC LIMIT 1) AS top_category,
        (SELECT CAST(SUM(CASE WHEN stf.o07 <> c.h02 THEN 1 ELSE 0 END) AS REAL) / COUNT(*) FROM pay p4 JOIN stf ON stf.o01 = p4.p03 WHERE p4.p02 = sd.customer_id AND date(p4.p06) = sd.p_date) AS off_store_share
    FROM suspicious_days sd
    JOIN cus c ON c.h01 = sd.customer_id
    JOIN adr ON adr.e01 = c.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
)
SELECT
    p_date,
    customer_name,
    country,
    city,
    daily_sum,
    daily_count,
    off_store_share,
    top_category,
    DENSE_RANK() OVER (ORDER BY (daily_sum / NULLIF(avg_sum_30d, 0)) + daily_count DESC) AS risk_rank
FROM customer_details
ORDER BY risk_rank ASC;