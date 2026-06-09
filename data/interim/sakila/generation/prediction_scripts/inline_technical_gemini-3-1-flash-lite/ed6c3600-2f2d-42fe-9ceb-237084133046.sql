WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS pay_date,
        SUM(p.p05) AS daily_sum,
        COUNT(*) AS daily_count,
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
        (SELECT AVG(val*val) FROM (SELECT daily_sum as val FROM daily_stats ds2 WHERE ds2.customer_id = ds.customer_id AND ds2.pay_date >= date(ds.pay_date, '-30 days') AND ds2.pay_date < ds.pay_date) ) - 
        (SELECT AVG(val)*AVG(val) FROM (SELECT daily_sum as val FROM daily_stats ds2 WHERE ds2.customer_id = ds.customer_id AND ds2.pay_date >= date(ds.pay_date, '-30 days') AND ds2.pay_date < ds.pay_date) ) AS var_sum_30d
    FROM daily_stats ds
),
anomalies AS (
    SELECT
        ws.*,
        (daily_sum - avg_sum_30d) / NULLIF(SQRT(ABS(var_sum_30d)), 0) AS z_score_sum
    FROM window_stats ws
    WHERE avg_sum_30d IS NOT NULL
      AND (daily_sum > avg_sum_30d + 3 * SQRT(ABS(var_sum_30d)) OR daily_count > avg_count_30d * 3)
),
top_category AS (
    SELECT customer_id, pay_date, category_name
    FROM (
        SELECT p.p02 as customer_id, date(p.p06) as pay_date, cat.g02 as category_name, COUNT(*) as cnt,
               ROW_NUMBER() OVER(PARTITION BY p.p02, date(p.p06) ORDER BY COUNT(*) DESC) as rn
        FROM pay p
        JOIN ren r ON p.p04 = r.q01
        JOIN inv i ON r.q03 = i.n01
        JOIN flc ON i.n02 = flc.l01
        JOIN cat ON flc.l02 = cat.g01
        GROUP BY p.p02, date(p.p06), cat.g02
    ) WHERE rn = 1
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
    tc.category_name AS primary_category,
    DENSE_RANK() OVER (ORDER BY a.z_score_sum DESC) AS risk_rank
FROM anomalies a
JOIN cus c ON a.customer_id = c.h01
JOIN adr ON c.h06 = adr.e01
JOIN cty ON adr.e05 = cty.d01
JOIN cnt ON cty.d03 = cnt.c01
LEFT JOIN top_category tc ON a.customer_id = tc.customer_id AND a.pay_date = tc.pay_date
ORDER BY risk_rank;