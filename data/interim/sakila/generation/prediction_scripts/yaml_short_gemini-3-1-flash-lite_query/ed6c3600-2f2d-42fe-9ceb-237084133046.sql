WITH daily_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(p.p05) AS daily_sum,
        COUNT(*) AS daily_count,
        GROUP_CONCAT(p.p03) AS staff_ids,
        GROUP_CONCAT(p.p04) AS rental_ids
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
        (SELECT STDEV(d.daily_sum) FROM daily_stats d 
         WHERE d.customer_id = ds.customer_id 
           AND d.payment_date >= date(ds.payment_date, '-30 days') 
           AND d.payment_date < ds.payment_date) AS stddev_sum_30d,
        COUNT(*) OVER (
            PARTITION BY ds.customer_id 
            ORDER BY ds.payment_date 
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS history_days
    FROM daily_stats ds
),
suspicious_days AS (
    SELECT *
    FROM history_stats
    WHERE history_days >= 15
      AND (daily_sum > avg_sum_30d + 3 * COALESCE(stddev_sum_30d, 0) 
           OR daily_count > 5)
),
category_counts AS (
    SELECT 
        r.q01 AS rental_id,
        c.g02 AS category_name
    FROM ren r
    JOIN inv i ON r.q03 = i.n01
    JOIN flc fc ON i.n02 = fc.l01
    JOIN cat c ON fc.l02 = c.g01
),
final_report AS (
    SELECT
        sd.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        (SELECT COUNT(*) FROM pay p 
         JOIN stf s ON p.p03 = s.o01 
         WHERE p.p02 = sd.customer_id AND date(p.p06) = sd.payment_date 
           AND s.o07 <> c.h02) * 1.0 / sd.daily_count AS off_home_store_share,
        (SELECT category_name FROM category_counts cc 
         WHERE cc.rental_id IN (SELECT value FROM json_each('[' || sd.rental_ids || ']'))
         GROUP BY category_name ORDER BY COUNT(*) DESC LIMIT 1) AS top_category,
        RANK() OVER (ORDER BY (sd.daily_sum / NULLIF(sd.avg_sum_30d, 0)) DESC) AS risk_rank
    FROM suspicious_days sd
    JOIN cus c ON sd.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ON a.e05 = cty.d01
    JOIN cnt ON cty.d03 = cnt.c01
)
SELECT * FROM final_report ORDER BY risk_rank;