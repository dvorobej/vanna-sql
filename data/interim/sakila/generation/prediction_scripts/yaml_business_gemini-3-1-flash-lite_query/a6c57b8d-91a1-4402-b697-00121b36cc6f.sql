WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(p.p01) AS payment_count
    FROM pay AS p
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_avg AS (
    SELECT
        customer_id,
        AVG(monthly_amount) AS avg_monthly_amount
    FROM monthly_stats
    GROUP BY customer_id
),
country_stats AS (
    SELECT
        c.h01 AS customer_id,
        co.c01 AS country_id,
        co.c02 AS country_name,
        ci.d02 AS city_name,
        PERCENT_RANK() OVER (PARTITION BY co.c01, ms.payment_month ORDER BY ms.monthly_amount DESC) AS country_percent_rank
    FROM monthly_stats AS ms
    JOIN cus AS c ON c.h01 = ms.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
),
top_staff_per_month AS (
    SELECT customer_id, payment_month, staff_id
    FROM (
        SELECT p.p02 AS customer_id, strftime('%Y-%m', p.p06) AS payment_month, p.p03 AS staff_id,
               SUM(p.p05) AS staff_sum,
               ROW_NUMBER() OVER (PARTITION BY p.p02, strftime('%Y-%m', p.p06) ORDER BY SUM(p.p05) DESC) as rn
        FROM pay AS p
        GROUP BY p.p02, strftime('%Y-%m', p.p06), p.p03
    ) WHERE rn = 1
)
SELECT
    ms.customer_id,
    cs.country_name,
    cs.city_name,
    ms.payment_month,
    ROUND(ms.monthly_amount, 2) AS monthly_amount,
    ms.payment_count,
    ROUND(ms.monthly_amount - ca.avg_monthly_amount, 2) AS deviation_from_avg,
    RANK() OVER (PARTITION BY cs.country_id, ms.payment_month ORDER BY ms.monthly_amount DESC) AS country_rank,
    stf.o02 || ' ' || stf.o03 AS top_staff_name
FROM monthly_stats AS ms
JOIN customer_avg AS ca ON ca.customer_id = ms.customer_id
JOIN country_stats AS cs ON cs.customer_id = ms.customer_id
JOIN top_staff_per_month AS tsm ON tsm.customer_id = ms.customer_id AND tsm.payment_month = ms.payment_month
JOIN stf ON stf.o01 = tsm.staff_id
WHERE ms.monthly_amount > (2 * ca.avg_monthly_amount)
  AND cs.country_percent_rank <= 0.10
ORDER BY ms.payment_month, cs.country_name, country_rank;