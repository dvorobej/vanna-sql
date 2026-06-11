WITH daily_customer_stats AS (
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
        dcs.*,
        AVG(dcs.daily_sum) OVER (
            PARTITION BY dcs.customer_id 
            ORDER BY dcs.payment_date 
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS avg_sum_30d,
        (SELECT STDEV(d.daily_sum) FROM daily_customer_stats d 
         WHERE d.customer_id = dcs.customer_id 
           AND d.payment_date >= date(dcs.payment_date, '-30 days') 
           AND d.payment_date < dcs.payment_date) AS stddev_sum_30d,
        COUNT(*) OVER (
            PARTITION BY dcs.customer_id 
            ORDER BY dcs.payment_date 
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS history_count
    FROM daily_customer_stats dcs
),
suspicious_days AS (
    SELECT *
    FROM history_stats
    WHERE history_count >= 10
      AND (daily_sum > avg_sum_30d + 3 * COALESCE(stddev_sum_30d, 0) OR daily_count > 10)
),
details AS (
    SELECT
        sd.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        (SELECT st.o02 || ' ' || st.o03 FROM stf st WHERE st.o01 = (SELECT p.p03 FROM pay p WHERE p.p02 = sd.customer_id AND date(p.p06) = sd.payment_date GROUP BY p.p03 ORDER BY COUNT(*) DESC LIMIT 1)) AS top_staff,
        (SELECT cat.g02 FROM cat 
         JOIN flc ON flc.l02 = cat.g01 
         JOIN inv ON inv.n02 = flc.l01 
         JOIN ren ON ren.q03 = inv.n01 
         WHERE ren.q04 = sd.customer_id AND date(ren.q02) = sd.payment_date 
         GROUP BY cat.g02 ORDER BY COUNT(*) DESC LIMIT 1) AS top_category,
        (SELECT CAST(SUM(CASE WHEN stf.o07 <> c.h02 THEN 1 ELSE 0 END) AS REAL) / COUNT(*) 
         FROM pay p JOIN stf ON stf.o01 = p.p03 
         WHERE p.p02 = sd.customer_id AND date(p.p06) = sd.payment_date) AS off_home_store_share
    FROM suspicious_days sd
    JOIN cus c ON c.h01 = sd.customer_id
    JOIN adr ON adr.e01 = c.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
)
SELECT
    payment_date,
    customer_name,
    country,
    city,
    daily_sum,
    daily_count,
    off_home_store_share,
    top_staff,
    top_category,
    DENSE_RANK() OVER (ORDER BY (daily_sum / NULLIF(avg_sum_30d, 0)) DESC) AS risk_rank
FROM details
ORDER BY risk_rank ASC;