WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(p.p01) AS payment_count,
        c.h06 AS address_id,
        c.h02 AS store_id
    FROM pay p
    JOIN cus c ON p.p02 = c.h01
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        co.c01 AS country_id,
        co.c02 AS country_name,
        ct.d02 AS city_name
    FROM cus c
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ct ON a.e05 = ct.d01
    JOIN cnt co ON ct.d03 = co.c01
),
monthly_with_avg AS (
    SELECT
        mcs.*,
        AVG(mcs.monthly_amount) OVER (PARTITION BY mcs.customer_id) AS personal_avg_monthly_amount
    FROM monthly_customer_stats mcs
),
country_stats AS (
    SELECT
        cg.country_id,
        mwa.payment_month,
        mwa.monthly_amount,
        PERCENT_RANK() OVER (PARTITION BY cg.country_id, mwa.payment_month ORDER BY mwa.monthly_amount) AS country_percentile
    FROM monthly_with_avg mwa
    JOIN customer_geo cg ON mwa.customer_id = cg.customer_id
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
    mwa.customer_id,
    cg.country_name,
    cg.city_name,
    mwa.payment_month,
    mwa.monthly_amount,
    mwa.payment_count,
    ROUND(mwa.monthly_amount / NULLIF(mwa.personal_avg_monthly_amount, 0), 2) AS deviation_from_avg,
    RANK() OVER (PARTITION BY cg.country_id, mwa.payment_month ORDER BY mwa.monthly_amount DESC) AS country_rank,
    ts.staff_id,
    s.h03 AS staff_first_name,
    s.h04 AS staff_last_name
FROM monthly_with_avg mwa
JOIN customer_geo cg ON mwa.customer_id = cg.customer_id
JOIN country_stats cs ON cg.country_id = cs.country_id AND mwa.payment_month = cs.payment_month AND mwa.monthly_amount = cs.monthly_amount
JOIN top_staff_per_month ts ON mwa.customer_id = ts.customer_id AND mwa.payment_month = ts.payment_month AND ts.rn = 1
JOIN cus s ON ts.staff_id = s.h01
WHERE mwa.monthly_amount > 2 * mwa.personal_avg_monthly_amount
  AND cs.country_percentile >= 0.9
ORDER BY cg.country_name, mwa.payment_month, country_rank;