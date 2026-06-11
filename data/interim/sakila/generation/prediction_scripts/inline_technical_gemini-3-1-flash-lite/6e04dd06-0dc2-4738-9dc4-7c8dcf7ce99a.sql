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
moving_avg AS (
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
        AVG(monthly_amount) AS median_monthly_amount,
        -- SQLite не имеет встроенной функции PERCENTILE_CONT, используем аппроксимацию через сортировку
        (SELECT monthly_amount FROM monthly_customer_stats m2 
         WHERE m2.country_id = m1.country_id AND m2.payment_month = m1.payment_month 
         ORDER BY monthly_amount LIMIT 1 OFFSET (SELECT COUNT(*) FROM monthly_customer_stats m3 WHERE m3.country_id = m1.country_id AND m3.payment_month = m1.payment_month) * 95 / 100) AS p95_monthly_amount
    FROM monthly_customer_stats m1
    GROUP BY country_id, payment_month
)
SELECT
    mcs.customer_id,
    mcs.customer_name,
    mcs.country_name,
    mcs.payment_month,
    ROUND(mcs.monthly_amount, 2) AS monthly_amount,
    mcs.payment_count,
    mcs.distinct_staff_count,
    mcs.distinct_store_count
FROM moving_avg mcs
JOIN country_stats cs ON mcs.country_id = cs.country_id AND mcs.payment_month = cs.payment_month
WHERE mcs.monthly_amount >= 3.0 * COALESCE(mcs.avg_prev_3_months, 0)
  AND mcs.monthly_amount >= 2.0 * cs.median_monthly_amount
  AND mcs.monthly_amount >= cs.p95_monthly_amount
ORDER BY mcs.payment_month, mcs.country_name, mcs.monthly_amount DESC;