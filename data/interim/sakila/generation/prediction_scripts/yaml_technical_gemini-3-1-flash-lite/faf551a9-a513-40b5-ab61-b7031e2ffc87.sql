WITH daily_customer_payments AS (
    SELECT
        p.p02 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        c.h02 AS store_id,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        DATE(p.p06) AS payment_date,
        SUM(p.p05) AS day_amount,
        COUNT(p.p01) AS payment_count
    FROM pay AS p
    JOIN cus AS c ON p.p02 = c.h01
    JOIN adr ON c.h06 = adr.e01
    JOIN cty ON adr.e05 = cty.d01
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
        MAX(CASE WHEN rn >= cnt * 0.95 THEN day_amount END) AS p95_day_amount
    FROM (
        SELECT
            country_id,
            payment_date,
            day_amount,
            ROW_NUMBER() OVER (PARTITION BY country_id, payment_date ORDER BY day_amount) AS rn,
            COUNT(*) OVER (PARTITION BY country_id, payment_date) AS cnt
        FROM daily_customer_payments
    )
    GROUP BY country_id, payment_date
),
suspicious_events AS (
    SELECT
        dwh.*,
        cp.p95_day_amount,
        (dwh.day_amount - dwh.avg_30d) AS deviation
    FROM daily_with_history AS dwh
    JOIN country_percentiles AS cp 
      ON dwh.country_id = cp.country_id 
     AND dwh.payment_date = cp.payment_date
    WHERE dwh.avg_30d > 0
      AND dwh.day_amount >= 3 * dwh.avg_30d
      AND dwh.day_amount > cp.p95_day_amount
)
SELECT
    payment_date,
    first_name,
    last_name,
    country_name,
    city_name,
    store_id,
    payment_count,
    ROUND(day_amount, 2) AS day_amount,
    ROUND(avg_30d, 2) AS avg_30d,
    ROUND(deviation, 2) AS deviation,
    RANK() OVER (PARTITION BY country_id ORDER BY deviation DESC) AS country_rank
FROM suspicious_events
ORDER BY deviation DESC;