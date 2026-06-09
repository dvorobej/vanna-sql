WITH monthly_customer_stats AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cn.c01 AS country_id,
        cn.c02 AS country_name,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT c.h02) AS distinct_store_count
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS cn ON cn.c01 = ct.d03
    GROUP BY c.h01, cn.c01, strftime('%Y-%m', p.p06)
),
moving_avg_stats AS (
    SELECT
        *,
        AVG(monthly_amount) OVER (
            PARTITION BY customer_id 
            ORDER BY payment_month 
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS avg_prev_3_months
    FROM monthly_customer_stats
),
country_stats AS (
    SELECT
        country_id,
        payment_month,
        -- Медиана через PERCENTILE_CONT (эмуляция для SQLite)
        AVG(monthly_amount) OVER (PARTITION BY country_id, payment_month) AS country_avg,
        -- 95-й процентиль (эмуляция через ROW_NUMBER)
        MAX(monthly_amount) OVER (PARTITION BY country_id, payment_month) AS country_max,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY monthly_amount) OVER (PARTITION BY country_id, payment_month) AS median_country_amount,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY monthly_amount) OVER (PARTITION BY country_id, payment_month) AS p95_country_amount
    FROM monthly_customer_stats
)
SELECT
    m.customer_id,
    m.customer_name,
    m.payment_month,
    m.monthly_amount,
    m.avg_prev_3_months,
    c.median_country_amount,
    c.p95_country_amount
FROM moving_avg_stats AS m
JOIN country_stats AS c 
  ON m.country_id = c.country_id 
  AND m.payment_month = c.payment_month
WHERE m.monthly_amount >= 3.0 * COALESCE(m.avg_prev_3_months, 0)
  AND m.monthly_amount >= 2.0 * c.median_country_amount
  AND m.monthly_amount >= c.p95_country_amount
ORDER BY m.payment_month, m.monthly_amount DESC;