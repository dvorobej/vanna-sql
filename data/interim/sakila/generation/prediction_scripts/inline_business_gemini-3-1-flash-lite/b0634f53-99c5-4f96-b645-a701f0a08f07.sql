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
customer_info AS (
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
store_countries AS (
    SELECT
        s.j01 AS store_id,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name
    FROM sto AS s
    JOIN adr AS a ON a.e01 = s.j03
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt ON cnt.c01 = ci.d03
),
suspicious_days AS (
    SELECT
        dp.*,
        ci.customer_name,
        ci.country_id,
        ci.country_name,
        (SELECT SUM(prev.day_amount) / 30.0
         FROM daily_payments AS prev
         WHERE prev.customer_id = dp.customer_id
           AND prev.payment_date >= date(dp.payment_date, '-30 day')
           AND prev.payment_date < dp.payment_date) AS avg_30d
    FROM daily_payments AS dp
    JOIN customer_info AS ci ON ci.customer_id = dp.customer_id
    WHERE dp.payment_count >= 3
),
filtered_suspicious AS (
    SELECT
        sd.*,
        (SELECT COUNT(DISTINCT sc.country_id)
         FROM store_countries AS sc
         WHERE instr(',' || sd.store_ids || ',', ',' || sc.store_id || ',') > 0
           AND sc.country_id <> sd.country_id) AS foreign_store_count
    FROM suspicious_days AS sd
    WHERE sd.day_amount >= 2.0 * sd.avg_30d
      AND sd.avg_30d > 0
)
SELECT
    fs.customer_id,
    fs.customer_name,
    fs.country_name,
    fs.payment_date,
    fs.payment_count,
    ROUND(fs.day_amount, 2) AS day_amount,
    ROUND(fs.avg_30d, 2) AS avg_30d,
    fs.staff_count,
    fs.store_count,
    RANK() OVER (PARTITION BY fs.country_id ORDER BY (fs.day_amount / fs.avg_30d) DESC) AS suspicion_rank
FROM filtered_suspicious AS fs
WHERE fs.foreign_store_count > 0
ORDER BY fs.country_name, suspicion_rank;