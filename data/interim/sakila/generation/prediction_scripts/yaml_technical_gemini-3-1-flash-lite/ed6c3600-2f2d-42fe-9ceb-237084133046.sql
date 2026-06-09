WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS pay_date,
        SUM(p.p05) AS daily_sum,
        COUNT(p.p01) AS daily_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        SUM(CASE WHEN s.o07 <> c.h02 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS foreign_store_ratio
    FROM pay p
    JOIN cus c ON p.p02 = c.h01
    JOIN stf s ON p.p03 = s.o01
    GROUP BY p.p02, date(p.p06)
),
window_stats AS (
    SELECT
        ds.*,
        AVG(ds.daily_sum) OVER (PARTITION BY ds.customer_id ORDER BY ds.pay_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) AS avg_sum_30d,
        AVG(ds.daily_count) OVER (PARTITION BY ds.customer_id ORDER BY ds.pay_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) AS avg_count_30d,
        (SELECT AVG(val * val) FROM (SELECT daily_sum AS val FROM daily_stats ds2 WHERE ds2.customer_id = ds.customer_id AND ds2.pay_date >= date(ds.pay_date, '-30 days') AND ds2.pay_date < ds.pay_date)) - (AVG(ds.daily_sum) OVER (PARTITION BY ds.customer_id ORDER BY ds.pay_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) * AVG(ds.daily_sum) OVER (PARTITION BY ds.customer_id ORDER BY ds.pay_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING)) AS var_sum_30d
    FROM daily_stats ds
),
anomalies AS (
    SELECT
        ws.*,
        SQRT(ABS(ws.var_sum_30d)) AS std_sum_30d
    FROM window_stats ws
    WHERE ws.avg_sum_30d IS NOT NULL
      AND (ws.daily_sum > ws.avg_sum_30d + 3 * SQRT(ABS(ws.var_sum_30d)) OR ws.daily_count > ws.avg_count_30d * 3)
),
top_staff_cat AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS pay_date,
        (SELECT o01 FROM pay p2 JOIN stf s2 ON p2.p03 = s2.o01 WHERE p2.p02 = p.p02 AND date(p2.p06) = date(p.p06) GROUP BY o01 ORDER BY COUNT(*) DESC LIMIT 1) AS top_staff_id,
        (SELECT cat.g02 FROM pay p3 JOIN ren r ON p3.p04 = r.q01 JOIN inv i ON r.q03 = i.n01 JOIN flc f ON i.n02 = f.l01 JOIN cat ON f.l02 = cat.g01 WHERE p3.p02 = p.p02 AND date(p3.p06) = date(p.p06) GROUP BY cat.g02 ORDER BY COUNT(*) DESC LIMIT 1) AS top_cat
    FROM pay p
    GROUP BY p.p02, date(p.p06)
)
SELECT
    a.customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    a.pay_date,
    a.daily_sum,
    a.daily_count,
    a.foreign_store_ratio,
    tsc.top_staff_id,
    tsc.top_cat,
    RANK() OVER (ORDER BY (a.daily_sum / NULLIF(a.avg_sum_30d, 0)) DESC) AS risk_rank
FROM anomalies a
JOIN cus c ON a.customer_id = c.h01
JOIN adr ON c.h06 = adr.e01
JOIN cty ON adr.e05 = cty.d01
JOIN cnt ON cty.d03 = cnt.c01
JOIN top_staff_cat tsc ON a.customer_id = tsc.customer_id AND a.pay_date = tsc.pay_date
ORDER BY risk_rank;