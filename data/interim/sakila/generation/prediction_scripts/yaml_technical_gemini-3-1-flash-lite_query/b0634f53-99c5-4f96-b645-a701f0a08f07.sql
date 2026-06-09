WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(p.p05) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        GROUP_CONCAT(DISTINCT s.o07) AS store_ids
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY p.p02, date(p.p06)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt ON cnt.c01 = ci.d03
),
store_geo AS (
    SELECT
        s.j01 AS store_id,
        cnt.c02 AS store_country_name
    FROM sto AS s
    JOIN adr AS a ON a.e01 = s.j03
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt ON cnt.c01 = ci.d03
),
suspicious_days AS (
    SELECT
        dp.*,
        cg.customer_name,
        cg.country_name,
        (
            SELECT SUM(p2.p05) / 30.0
            FROM pay AS p2
            WHERE p2.p02 = dp.customer_id
              AND p2.p06 >= date(dp.payment_date, '-30 days')
              AND p2.p06 < dp.payment_date
        ) AS avg_30d_amount
    FROM daily_payments AS dp
    JOIN customer_geo AS cg ON cg.customer_id = dp.customer_id
    WHERE dp.payment_count >= 3
      AND dp.staff_count >= 2
      AND dp.store_count >= 2
),
filtered_suspicious AS (
    SELECT
        sd.*,
        (SELECT GROUP_CONCAT(DISTINCT sg.store_country_name)
         FROM store_geo AS sg
         WHERE instr(',' || sd.store_ids || ',', ',' || sg.store_id || ',') > 0
        ) AS involved_store_countries
    FROM suspicious_days AS sd
    WHERE sd.day_amount >= 2 * sd.avg_30d_amount
)
SELECT
    fs.customer_name,
    fs.payment_date,
    fs.country_name,
    fs.payment_count,
    ROUND(fs.day_amount, 2) AS day_amount,
    ROUND(fs.avg_30d_amount, 2) AS avg_30d_amount,
    fs.staff_count,
    fs.store_count,
    fs.involved_store_countries,
    RANK() OVER (
        PARTITION BY fs.country_name
        ORDER BY (fs.day_amount / NULLIF(fs.avg_30d_amount, 0)) DESC
    ) AS suspicion_rank_in_country
FROM filtered_suspicious AS fs
WHERE fs.involved_store_countries LIKE '%' || fs.country_name || '%'
  AND fs.involved_store_countries NOT LIKE fs.country_name
ORDER BY fs.country_name, suspicion_rank_in_country;