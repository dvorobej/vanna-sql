WITH daily_customer_payments AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        SUM(p.p05) AS day_amount,
        COUNT(p.p01) AS payment_count
    FROM pay AS p
    GROUP BY p.p02, DATE(p.p06)
),
customer_stats AS (
    SELECT
        dcp.*,
        (
            SELECT AVG(prev.day_amount)
            FROM daily_customer_payments AS prev
            WHERE prev.customer_id = dcp.customer_id
              AND prev.payment_date >= DATE(dcp.payment_date, '-30 days')
              AND prev.payment_date < dcp.payment_date
        ) AS avg_prev_30d
    FROM daily_customer_payments AS dcp
),
country_percentiles AS (
    SELECT
        c.c01 AS country_id,
        dcp.payment_date,
        -- Вычисление 95-го перцентиля через сортировку и фильтрацию
        (SELECT val FROM (
            SELECT day_amount AS val, PERCENT_RANK() OVER (ORDER BY day_amount) as pr
            FROM daily_customer_payments AS dcp2
            JOIN cus AS c2 ON c2.h01 = dcp2.customer_id
            JOIN adr AS a2 ON a2.e01 = c2.h06
            JOIN cty AS ci2 ON ci2.d01 = a2.e05
            WHERE ci2.d03 = c.c01 AND dcp2.payment_date = dcp.payment_date
        ) WHERE pr >= 0.95 LIMIT 1) AS p95_day_amount
    FROM cnt AS c
    JOIN daily_customer_payments AS dcp
    GROUP BY c.c01, dcp.payment_date
)
SELECT
    cs.payment_date,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cnt.c02 AS country_name,
    cty.d02 AS city_name,
    c.h02 AS store_id,
    cs.payment_count,
    ROUND(cs.day_amount, 2) AS day_amount,
    ROUND(cs.avg_prev_30d, 2) AS avg_prev_30d,
    ROUND(cs.day_amount - cs.avg_prev_30d, 2) AS deviation,
    RANK() OVER (PARTITION BY cnt.c01 ORDER BY (cs.day_amount / NULLIF(cs.avg_prev_30d, 0)) DESC) AS country_rank
FROM customer_stats AS cs
JOIN cus AS c ON c.h01 = cs.customer_id
JOIN adr AS a ON a.e01 = c.h06
JOIN cty ON cty.d01 = a.e05
JOIN cnt ON cnt.c01 = cty.d03
JOIN country_percentiles AS cp ON cp.country_id = cnt.c01 AND cp.payment_date = cs.payment_date
WHERE cs.avg_prev_30d > 0
  AND cs.day_amount >= 3 * cs.avg_prev_30d
  AND cs.day_amount > cp.p95_day_amount
ORDER BY (cs.day_amount / NULLIF(cs.avg_prev_30d, 0)) DESC;