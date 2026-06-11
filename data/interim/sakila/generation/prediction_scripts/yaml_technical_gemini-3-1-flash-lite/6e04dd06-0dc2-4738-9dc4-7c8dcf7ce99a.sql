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
monthly_with_history AS (
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
        -- Медиана через PERCENTILE_CONT (или аппроксимация через ROW_NUMBER)
        AVG(monthly_amount) OVER (PARTITION BY country_id, payment_month) AS country_median,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY monthly_amount) OVER (PARTITION BY country_id, payment_month) AS p95_country_amount
    FROM monthly_customer_stats
)
SELECT
    m.customer_id,
    m.customer_name,
    m.country_name,
    m.payment_month,
    ROUND(m.monthly_amount, 2) AS monthly_amount,
    m.payment_count,
    m.distinct_staff_count,
    m.distinct_store_count
FROM monthly_with_history m
JOIN country_stats cs 
  ON m.country_id = cs.country_id 
  AND m.payment_month = cs.payment_month
WHERE m.monthly_amount >= 3.0 * COALESCE(m.avg_prev_3_months, 0)
  AND m.monthly_amount >= 2.0 * cs.country_median
  AND m.monthly_amount >= cs.p95_country_amount
ORDER BY m.payment_month, m.country_name, m.monthly_amount DESC;