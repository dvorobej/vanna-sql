WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        SUM(p.p05) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        GROUP_CONCAT(DISTINCT s.o07) AS store_ids
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY p.p02, DATE(p.p06)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        cnt.c02 AS customer_country
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS cnt ON cnt.c01 = ci.d03
),
store_geo AS (
    SELECT
        sto.j01 AS store_id,
        cnt.c02 AS store_country
    FROM sto
    JOIN adr AS a ON a.e01 = sto.j03
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS cnt ON cnt.c01 = ci.d03
),
suspicious_days AS (
    SELECT
        dp.*,
        cg.customer_country,
        (SELECT SUM(prev.day_amount) / 30.0 
         FROM daily_payments AS prev 
         WHERE prev.customer_id = dp.customer_id 
           AND prev.payment_date >= DATE(dp.payment_date, '-30 days') 
           AND prev.payment_date < dp.payment_date) AS avg_30d
    FROM daily_payments AS dp
    JOIN customer_geo AS cg ON cg.customer_id = dp.customer_id
    WHERE dp.payment_count >= 3
),
filtered_suspicious AS (
    SELECT
        sd.*,
        (SELECT COUNT(DISTINCT sg.store_country) 
         FROM store_geo AS sg 
         WHERE ',' || sd.store_ids || ',' LIKE '%,' || sg.store_id || ',%') AS distinct_store_countries
    FROM suspicious_days AS sd
    WHERE sd.day_amount >= 2.0 * sd.avg_30d
      AND EXISTS (
          SELECT 1 FROM store_geo AS sg 
          WHERE ',' || sd.store_ids || ',' LIKE '%,' || sg.store_id || ',%' 
            AND sg.store_country <> sd.customer_country
      )
)
SELECT
    fs.customer_id,
    fs.payment_date,
    fs.customer_country,
    fs.payment_count,
    ROUND(fs.day_amount, 2) AS day_amount,
    ROUND(fs.avg_30d, 2) AS avg_30d,
    fs.staff_count,
    fs.store_count,
    RANK() OVER (PARTITION BY fs.customer_country ORDER BY (fs.day_amount / NULLIF(fs.avg_30d, 0)) DESC) AS suspicion_rank
FROM filtered_suspicious AS fs
ORDER BY fs.customer_country, suspicion_rank;