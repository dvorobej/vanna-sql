WITH monthly_customer_stats AS (
    SELECT
        c.h01 AS customer_id,
        cn.c01 AS country_id,
        cn.c02 AS country_name,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT c.h02) AS distinct_store_count
    FROM pay AS p
    JOIN cus AS c ON p.p02 = c.h01
    JOIN adr AS a ON c.h06 = a.e01
    JOIN cty AS ct ON a.e05 = ct.d01
    JOIN cnt AS cn ON ct.d03 = cn.c01
    GROUP BY c.h01, cn.c01, cn.c02, strftime('%Y-%m', p.p06)
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
        monthly_amount,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY monthly_amount) OVER (PARTITION BY country_id, payment_month) AS median_country_amount,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY monthly_amount) OVER (PARTITION BY country_id, payment_month) AS p95_country_amount
    FROM monthly_customer_stats
)
SELECT
    m.customer_id,
    m.payment_month,
    m.monthly_amount,
    m.payment_count,
    m.avg_prev_3_months,
    cs.median_country_amount,
    cs.p95_country_amount
FROM monthly_with_history m
JOIN country_stats cs 
  ON m.country_id = cs.country_id 
  AND m.payment_month = cs.payment_month 
  AND m.monthly_amount = cs.monthly_amount
WHERE m.avg_prev_3_months IS NOT NULL
  AND m.monthly_amount >= 3 * m.avg_prev_3_months
  AND m.monthly_amount >= 2 * cs.median_country_amount
  AND m.monthly_amount >= cs.p95_country_amount
ORDER BY m.payment_month, m.customer_id;