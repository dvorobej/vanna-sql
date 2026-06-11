WITH daily_customer_payments AS (
    SELECT
        p.p02 AS customer_id,
        c.h03,
        c.h04,
        c.h02 AS store_id,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        DATE(p.p06) AS payment_date,
        SUM(p.p05) AS day_amount,
        COUNT(p.p01) AS payment_count
    FROM pay AS p
    JOIN cus AS c ON p.p02 = c.h01
    JOIN adr AS a ON c.h06 = a.e01
    JOIN cty ON a.e05 = cty.d01
    JOIN cnt ON cty.d03 = cnt.c01
    GROUP BY p.p02, DATE(p.p06)
),
daily_with_history AS (
    SELECT
        dcp.*,
        (
            SELECT AVG(prev.day_amount)
            FROM daily_customer_payments AS prev
            WHERE prev.customer_id = dcp.customer_id
              AND prev.payment_date >= DATE(dcp.payment_date, '-30 days')
              AND prev.payment_date < dcp.payment_date
        ) AS avg_30d
    FROM daily_customer_payments AS dcp
),
country_percentiles AS (
    SELECT
        country_id,
        payment_date,
        -- SQLite не имеет встроенной функции PERCENTILE, используем метод ранжирования
        MAX(CASE WHEN rn >= (0.95 * total_count) THEN day_amount END) OVER (PARTITION BY country_id, payment_date) AS p95_day_amount
    FROM (
        SELECT
            country_id,
            payment_date,
            day_amount,
            ROW_NUMBER() OVER (PARTITION BY country_id, payment_date ORDER BY day_amount) AS rn,
            COUNT(*) OVER (PARTITION BY country_id, payment_date) AS total_count
        FROM daily_customer_payments
    ) AS sub
)
SELECT
    dwh.payment_date,
    dwh.h03,
    dwh.h04,
    dwh.country_name,
    dwh.city_name,
    dwh.store_id,
    dwh.payment_count,
    ROUND(dwh.day_amount, 2) AS day_amount,
    ROUND(dwh.avg_30d, 2) AS avg_30d,
    ROUND(dwh.day_amount - dwh.avg_30d, 2) AS deviation,
    RANK() OVER (PARTITION BY dwh.country_id ORDER BY dwh.day_amount DESC) AS country_rank
FROM daily_with_history AS dwh
JOIN country_percentiles AS cp 
  ON dwh.country_id = cp.country_id 
 AND dwh.payment_date = cp.payment_date
WHERE dwh.avg_30d > 0
  AND dwh.day_amount >= 3 * dwh.avg_30d
  AND dwh.day_amount >= cp.p95_day_amount
ORDER BY dwh.day_amount DESC;