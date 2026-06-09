WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(p.p01) AS payment_count
    FROM pay p
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_avg AS (
    SELECT
        customer_id,
        AVG(monthly_amount) AS avg_monthly_amount
    FROM monthly_customer_stats
    GROUP BY customer_id
),
country_stats AS (
    SELECT
        c.h01 AS customer_id,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY mcs.monthly_amount) OVER (PARTITION BY cnt.c01, mcs.payment_month) AS p90_country_amount
    FROM monthly_customer_stats mcs
    JOIN cus c ON c.h01 = mcs.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty cty ON cty.d01 = a.e05
    JOIN cnt cnt ON cnt.c01 = cty.d03
),
top_staff_per_month AS (
    SELECT * FROM (
        SELECT
            p.p02 AS customer_id,
            strftime('%Y-%m', p.p06) AS payment_month,
            p.p03 AS staff_id,
            ROW_NUMBER() OVER (PARTITION BY p.p02, strftime('%Y-%m', p.p06) ORDER BY SUM(p.p05) DESC) as rn
        FROM pay p
        GROUP BY p.p02, strftime('%Y-%m', p.p06), p.p03
    ) WHERE rn = 1
)
SELECT
    mcs.customer_id,
    cs.country_name,
    cs.city_name,
    mcs.payment_month,
    mcs.monthly_amount,
    mcs.payment_count,
    (mcs.monthly_amount / NULLIF(ca.avg_monthly_amount, 0)) AS deviation_from_avg,
    RANK() OVER (PARTITION BY cs.country_id, mcs.payment_month ORDER BY mcs.monthly_amount DESC) AS country_rank,
    ts.staff_id
FROM monthly_customer_stats mcs
JOIN customer_avg ca ON ca.customer_id = mcs.customer_id
JOIN country_stats cs ON cs.customer_id = mcs.customer_id
JOIN top_staff_per_month ts ON ts.customer_id = mcs.customer_id AND ts.payment_month = mcs.payment_month
WHERE mcs.monthly_amount > (2 * ca.avg_monthly_amount)
  AND mcs.monthly_amount >= cs.p90_country_amount
ORDER BY cs.country_name, mcs.payment_month, country_rank;