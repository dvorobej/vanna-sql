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
customer_yearly_avg AS (
    SELECT
        customer_id,
        AVG(monthly_amount) AS avg_monthly_amount
    FROM monthly_customer_stats
    GROUP BY customer_id
),
country_stats AS (
    SELECT
        c.h01 AS customer_id,
        co.c01 AS country_id,
        co.c02 AS country_name,
        ci.d02 AS city_name,
        PERCENT_RANK() OVER (PARTITION BY co.c01, mcs.payment_month ORDER BY mcs.monthly_amount DESC) AS country_percent_rank
    FROM monthly_customer_stats mcs
    JOIN cus c ON c.h01 = mcs.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ci ON ci.d01 = a.e05
    JOIN cnt co ON co.c01 = ci.d03
),
staff_monthly_max AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        p.p03 AS staff_id,
        SUM(p.p05) AS staff_amount
    FROM pay p
    GROUP BY p.p02, strftime('%Y-%m', p.p06), p.p03
),
top_staff AS (
    SELECT customer_id, payment_month, staff_id
    FROM (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY customer_id, payment_month ORDER BY staff_amount DESC) as rn
        FROM staff_monthly_max
    ) WHERE rn = 1
)
SELECT
    mcs.customer_id,
    cs.country_name,
    cs.city_name,
    mcs.payment_month,
    mcs.monthly_amount,
    mcs.payment_count,
    (mcs.monthly_amount - cya.avg_monthly_amount) AS deviation_from_avg,
    RANK() OVER (PARTITION BY cs.country_id, mcs.payment_month ORDER BY mcs.monthly_amount DESC) AS country_rank,
    stf.o02 || ' ' || stf.o03 AS top_staff_name
FROM monthly_customer_stats mcs
JOIN customer_yearly_avg cya ON cya.customer_id = mcs.customer_id
JOIN country_stats cs ON cs.customer_id = mcs.customer_id
JOIN top_staff ts ON ts.customer_id = mcs.customer_id AND ts.payment_month = mcs.payment_month
JOIN stf ON stf.o01 = ts.staff_id
WHERE mcs.monthly_amount > (2 * cya.avg_monthly_amount)
  AND cs.country_percent_rank <= 0.10
ORDER BY mcs.payment_month, cs.country_name, country_rank;