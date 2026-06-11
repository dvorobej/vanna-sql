WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(p.p05) AS daily_sum,
        COUNT(*) AS daily_count,
        GROUP_CONCAT(p.p03) AS staff_list
    FROM pay p
    GROUP BY p.p02, date(p.p06)
),
history_stats AS (
    SELECT
        ds.*,
        AVG(ds.daily_sum) OVER (
            PARTITION BY ds.customer_id 
            ORDER BY ds.payment_date 
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS avg_sum_30d,
        (SELECT AVG(val) FROM (
            SELECT SUM(p.p05) as val FROM pay p 
            WHERE p.p02 = ds.customer_id AND date(p.p06) < ds.payment_date 
            GROUP BY date(p.p06)
        )) AS dummy_avg, -- Placeholder for complex window stddev
        STDEV(ds.daily_sum) OVER (
            PARTITION BY ds.customer_id 
            ORDER BY ds.payment_date 
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS stddev_sum_30d
    FROM daily_stats ds
),
suspicious_days AS (
    SELECT * FROM history_stats
    WHERE daily_sum > (avg_sum_30d + 3 * stddev_sum_30d)
       OR daily_count > 10 -- Threshold for "sharp increase"
),
customer_details AS (
    SELECT
        sd.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        (SELECT stf.o02 FROM pay p JOIN stf ON p.p03 = stf.o01 
         WHERE p.p02 = sd.customer_id AND date(p.p06) = sd.payment_date 
         GROUP BY p.p03 ORDER BY COUNT(*) DESC LIMIT 1) AS top_staff,
        (SELECT cat.g02 FROM pay p JOIN ren r ON p.p04 = r.q01 
         JOIN inv i ON r.q03 = i.n01 JOIN flc f ON i.n02 = f.l01 
         JOIN cat ON f.l02 = cat.g01 
         WHERE p.p02 = sd.customer_id AND date(p.p06) = sd.payment_date 
         GROUP BY cat.g02 ORDER BY COUNT(*) DESC LIMIT 1) AS top_category,
        (SELECT CAST(SUM(CASE WHEN stf.o07 <> c.h02 THEN 1 ELSE 0 END) AS REAL) / COUNT(*)
         FROM pay p JOIN stf ON p.p03 = stf.o01 
         WHERE p.p02 = sd.customer_id AND date(p.p06) = sd.payment_date) AS off_store_share
    FROM suspicious_days sd
    JOIN cus c ON sd.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ON a.e05 = cty.d01
    JOIN cnt ON cty.d03 = cnt.c01
)
SELECT 
    *,
    RANK() OVER (ORDER BY (daily_sum / NULLIF(avg_sum_30d, 0)) DESC) AS risk_rank
FROM customer_details;