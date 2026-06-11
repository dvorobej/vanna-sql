WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(p.p01) AS payment_count,
        c.h06 AS address_id,
        c.h02 AS store_id
    FROM pay p
    JOIN cus c ON c.h01 = p.p02
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY p.p02, strftime('%Y-%m', p.p06), c.h06, c.h02
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
        cnt.c01 AS country_id,
        mcs.payment_month,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY mcs.monthly_amount) AS p90_amount
    FROM monthly_customer_stats mcs
    JOIN adr a ON a.e01 = mcs.address_id
    JOIN cty ct ON ct.d01 = a.e05
    JOIN cnt ON cnt.c01 = ct.d03
    GROUP BY cnt.c01, mcs.payment_month
),
top_staff_per_month AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        p.p03 AS staff_id,
        SUM(p.p05) AS staff_monthly_amount,
        ROW_NUMBER() OVER (PARTITION BY p.p02, strftime('%Y-%m', p.p06) ORDER BY SUM(p.p05) DESC) AS rn
    FROM pay p
    GROUP BY p.p02, strftime('%Y-%m', p.p06), p.p03
)
SELECT
    mcs.customer_id,
    co.c02 AS country,
    ct.d02 AS city,
    mcs.payment_month,
    mcs.monthly_amount,
    mcs.payment_count,
    (mcs.monthly_amount / NULLIF(ca.avg_monthly_amount, 0)) AS deviation_from_avg,
    RANK() OVER (PARTITION BY co.c01, mcs.payment_month ORDER BY mcs.monthly_amount DESC) AS country_rank,
    ts.staff_id,
    s.o02 AS staff_first_name,
    s.o03 AS staff_last_name
FROM monthly_customer_stats mcs
JOIN customer_avg ca ON ca.customer_id = mcs.customer_id
JOIN adr a ON a.e01 = mcs.address_id
JOIN cty ct ON ct.d01 = a.e05
JOIN cnt co ON co.c01 = ct.d03
JOIN country_stats cs ON cs.country_id = co.c01 AND cs.payment_month = mcs.payment_month
JOIN top_staff_per_month ts ON ts.customer_id = mcs.customer_id AND ts.payment_month = mcs.payment_month AND ts.rn = 1
JOIN stf s ON s.o01 = ts.staff_id
WHERE mcs.monthly_amount > (2 * ca.avg_monthly_amount)
  AND mcs.monthly_amount >= cs.p90_amount
ORDER BY co.c02, mcs.payment_month, country_rank;