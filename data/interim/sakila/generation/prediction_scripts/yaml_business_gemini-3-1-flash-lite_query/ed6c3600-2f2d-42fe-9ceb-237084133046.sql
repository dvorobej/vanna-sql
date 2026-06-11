WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(p.p05) AS daily_sum,
        COUNT(*) AS daily_count,
        SUM(CASE WHEN st.o07 <> cu.h02 THEN 1 ELSE 0 END) AS off_home_store_count,
        COUNT(*) AS total_daily_count
    FROM pay p
    JOIN cus cu ON cu.h01 = p.p02
    JOIN stf st ON st.o01 = p.p03
    GROUP BY p.p02, date(p.p06)
),
history_stats AS (
    SELECT
        ds.*,
        AVG(ds.daily_sum) OVER (PARTITION BY ds.customer_id ORDER BY ds.payment_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) AS avg_sum_30d,
        AVG(ds.daily_count) OVER (PARTITION BY ds.customer_id ORDER BY ds.payment_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) AS avg_count_30d,
        (SELECT AVG(val*val) FROM (SELECT ds2.daily_sum as val FROM daily_stats ds2 WHERE ds2.customer_id = ds.customer_id AND ds2.payment_date < ds.payment_date ORDER BY ds2.payment_date DESC LIMIT 30)) - 
        (SELECT AVG(val)*AVG(val) FROM (SELECT ds2.daily_sum as val FROM daily_stats ds2 WHERE ds2.customer_id = ds.customer_id AND ds2.payment_date < ds.payment_date ORDER BY ds2.payment_date DESC LIMIT 30)) AS var_sum_30d
    FROM daily_stats ds
),
suspicious_days AS (
    SELECT *,
        CASE 
            WHEN daily_sum > avg_sum_30d + 3 * SQRT(ABS(var_sum_30d)) THEN 1 
            WHEN daily_count > avg_count_30d * 3 THEN 1 
            ELSE 0 
        END AS is_suspicious
    FROM history_stats
    WHERE avg_sum_30d IS NOT NULL
),
top_staff AS (
    SELECT customer_id, payment_date, staff_id,
        ROW_NUMBER() OVER (PARTITION BY customer_id, payment_date ORDER BY cnt DESC) as rn
    FROM (SELECT p02 as customer_id, date(p06) as payment_date, p03 as staff_id, COUNT(*) as cnt FROM pay GROUP BY 1, 2, 3)
),
top_category AS (
    SELECT customer_id, payment_date, category_name,
        ROW_NUMBER() OVER (PARTITION BY customer_id, payment_date ORDER BY cnt DESC) as rn
    FROM (SELECT p.p02 as customer_id, date(p.p06) as payment_date, cat.g02 as category_name, COUNT(*) as cnt 
          FROM pay p JOIN ren r ON p.p04 = r.q01 JOIN inv i ON r.q03 = i.n01 JOIN flc fc ON i.n02 = fc.l01 JOIN cat ON fc.l02 = cat.g01 GROUP BY 1, 2, 3)
)
SELECT 
    sd.customer_id, sd.payment_date, 
    cu.h03 || ' ' || cu.h04 AS name, cnt.c02 AS country, cty.d02 AS city,
    sd.daily_sum, sd.daily_count,
    (sd.off_home_store_count * 1.0 / sd.total_daily_count) AS off_home_share,
    ts.staff_id AS top_staff, tc.category_name AS top_category,
    RANK() OVER (ORDER BY (sd.daily_sum - sd.avg_sum_30d) DESC) AS risk_rank
FROM suspicious_days sd
JOIN cus cu ON sd.customer_id = cu.h01
JOIN adr ON cu.h06 = adr.e01
JOIN cty ON adr.e05 = cty.d01
JOIN cnt ON cty.d03 = cnt.c01
JOIN top_staff ts ON sd.customer_id = ts.customer_id AND sd.payment_date = ts.payment_date AND ts.rn = 1
JOIN top_category tc ON sd.customer_id = tc.customer_id AND sd.payment_date = tc.payment_date AND tc.rn = 1
WHERE sd.is_suspicious = 1
ORDER BY risk_rank;