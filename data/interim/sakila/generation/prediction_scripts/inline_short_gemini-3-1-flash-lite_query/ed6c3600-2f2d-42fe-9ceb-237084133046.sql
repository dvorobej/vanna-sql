WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(p.p05) AS daily_sum,
        COUNT(*) AS daily_count,
        GROUP_CONCAT(p.p03) AS staff_ids
    FROM pay p
    GROUP BY p.p02, date(p.p06)
),
history_stats AS (
    SELECT
        ds.*,
        AVG(ds.daily_sum) OVER (PARTITION BY ds.customer_id ORDER BY ds.payment_date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) AS avg_sum_30d,
        (SELECT AVG(val) FROM (SELECT ds2.daily_sum AS val FROM daily_stats ds2 WHERE ds2.customer_id = ds.customer_id AND ds2.payment_date < ds.payment_date ORDER BY ds2.payment_date DESC LIMIT 30)) AS avg_sum,
        (SELECT AVG(val*val) - AVG(val)*AVG(val) FROM (SELECT ds2.daily_sum AS val FROM daily_stats ds2 WHERE ds2.customer_id = ds.customer_id AND ds2.payment_date < ds.payment_date ORDER BY ds2.payment_date DESC LIMIT 30)) AS var_sum
    FROM daily_stats ds
),
suspicious_days AS (
    SELECT
        hs.*,
        SQRT(ABS(hs.var_sum)) AS std_sum
    FROM history_stats hs
    WHERE hs.avg_sum IS NOT NULL
      AND (hs.daily_sum > hs.avg_sum + 3 * SQRT(ABS(hs.var_sum)) OR hs.daily_count > 10)
),
category_info AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        cat.g02 AS category_name,
        COUNT(*) AS cat_count
    FROM pay p
    JOIN ren r ON p.p04 = r.q01
    JOIN inv i ON r.q03 = i.n01
    JOIN flc fc ON i.n02 = fc.l01
    JOIN cat ON fc.l02 = cat.g01
    GROUP BY p.p02, date(p.p06), cat.g02
),
top_category AS (
    SELECT customer_id, payment_date, category_name
    FROM (SELECT *, ROW_NUMBER() OVER(PARTITION BY customer_id, payment_date ORDER BY cat_count DESC) as rn FROM category_info)
    WHERE rn = 1
)
SELECT
    sd.customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    sd.payment_date,
    sd.daily_sum,
    sd.daily_count,
    tc.category_name AS top_category,
    ROUND(1.0 * SUM(CASE WHEN stf.o07 <> c.h02 THEN 1 ELSE 0 END) OVER(PARTITION BY sd.customer_id, sd.payment_date) / sd.daily_count, 2) AS off_home_store_share,
    RANK() OVER (ORDER BY (sd.daily_sum / NULLIF(sd.avg_sum, 0)) DESC) AS risk_rank
FROM suspicious_days sd
JOIN cus c ON sd.customer_id = c.h01
JOIN adr ON c.h06 = adr.e01
JOIN cty ON adr.e05 = cty.d01
JOIN cnt ON cty.d03 = cnt.c01
JOIN stf ON stf.o01 IN (SELECT value FROM json_each('["' || REPLACE(sd.staff_ids, ',', '","') || '"]'))
LEFT JOIN top_category tc ON sd.customer_id = tc.customer_id AND sd.payment_date = tc.payment_date
GROUP BY sd.customer_id, sd.payment_date
ORDER BY risk_rank ASC;