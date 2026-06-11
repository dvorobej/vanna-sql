WITH monthly_stats AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cn.c02 AS country,
        ct.d02 AS city,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(p.p01) AS payment_count
    FROM pay AS p
    JOIN cus AS c ON p.p02 = c.h01
    JOIN adr AS a ON c.h06 = a.e01
    JOIN cty AS ct ON a.e05 = ct.d01
    JOIN cnt AS cn ON ct.d03 = cn.c01
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY c.h01, cn.c02, ct.d02, strftime('%Y-%m', p.p06)
),
customer_avg AS (
    SELECT
        customer_id,
        AVG(monthly_amount) AS avg_monthly_amount
    FROM monthly_stats
    GROUP BY customer_id
),
country_avg AS (
    SELECT
        country,
        payment_month,
        AVG(monthly_amount) AS avg_country_amount
    FROM monthly_stats
    GROUP BY country, payment_month
),
staff_max_pay AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        p.p03 AS staff_id,
        SUM(p.p05) AS staff_sum
    FROM pay AS p
    GROUP BY p.p02, strftime('%Y-%m', p.p06), p.p03
),
ranked_staff AS (
    SELECT
        customer_id,
        payment_month,
        staff_id,
        ROW_NUMBER() OVER (PARTITION BY customer_id, payment_month ORDER BY staff_sum DESC) as rn
    FROM staff_max_pay
)
SELECT
    ms.customer_name,
    ms.country,
    ms.city,
    ms.payment_month,
    ROUND(ms.monthly_amount, 2) AS monthly_amount,
    ms.payment_count,
    ROUND(ms.monthly_amount - ca.avg_monthly_amount, 2) AS deviation_from_personal_avg,
    RANK() OVER (PARTITION BY ms.country, ms.payment_month ORDER BY ms.monthly_amount DESC) AS country_rank,
    stf.o02 || ' ' || stf.o03 AS top_staff_name
FROM monthly_stats AS ms
JOIN customer_avg AS ca ON ms.customer_id = ca.customer_id
JOIN country_avg AS cna ON ms.country = cna.country AND ms.payment_month = cna.payment_month
JOIN ranked_staff AS rs ON ms.customer_id = rs.customer_id AND ms.payment_month = rs.payment_month AND rs.rn = 1
JOIN stf ON rs.staff_id = stf.o01
WHERE ms.monthly_amount > (ca.avg_monthly_amount * 1.5)
   OR ms.monthly_amount > (cna.avg_country_amount * 2)
ORDER BY ms.payment_month, country_rank;