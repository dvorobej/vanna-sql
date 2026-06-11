WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count
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
country_monthly_stats AS (
    SELECT
        c.c01 AS country_id,
        mcs.payment_month,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY mcs.monthly_amount) OVER (PARTITION BY c.c01, mcs.payment_month) AS p90_country_amount
    FROM monthly_customer_stats mcs
    JOIN cus cu ON mcs.customer_id = cu.h01
    JOIN adr a ON cu.h06 = a.e01
    JOIN cty ci ON a.e05 = ci.d01
    JOIN cnt c ON ci.d03 = c.c01
),
staff_monthly_max AS (
    SELECT
        customer_id,
        payment_month,
        staff_id,
        monthly_staff_amount
    FROM (
        SELECT
            p.p02 AS customer_id,
            strftime('%Y-%m', p.p06) AS payment_month,
            p.p03 AS staff_id,
            SUM(p.p05) AS monthly_staff_amount,
            ROW_NUMBER() OVER (PARTITION BY p.p02, strftime('%Y-%m', p.p06) ORDER BY SUM(p.p05) DESC) AS rn
        FROM pay p
        GROUP BY p.p02, strftime('%Y-%m', p.p06), p.p03
    ) WHERE rn = 1
)
SELECT
    mcs.customer_id,
    co.c02 AS country,
    ci.d02 AS city,
    mcs.payment_month,
    mcs.monthly_amount,
    mcs.payment_count,
    (mcs.monthly_amount - cya.avg_monthly_amount) AS deviation_from_avg,
    RANK() OVER (PARTITION BY co.c01, mcs.payment_month ORDER BY mcs.monthly_amount DESC) AS country_rank,
    st.o02 || ' ' || st.o03 AS top_staff_name
FROM monthly_customer_stats mcs
JOIN customer_yearly_avg cya ON mcs.customer_id = cya.customer_id
JOIN cus cu ON mcs.customer_id = cu.h01
JOIN adr a ON cu.h06 = a.e01
JOIN cty ci ON a.e05 = ci.d01
JOIN cnt co ON ci.d03 = co.c01
JOIN country_monthly_stats cms ON co.c01 = cms.country_id AND mcs.payment_month = cms.payment_month
JOIN staff_monthly_max smm ON mcs.customer_id = smm.customer_id AND mcs.payment_month = smm.payment_month
JOIN stf st ON smm.staff_id = st.o01
WHERE mcs.monthly_amount > (2 * cya.avg_monthly_amount)
  AND mcs.monthly_amount >= cms.p90_country_amount
GROUP BY mcs.customer_id, mcs.payment_month;