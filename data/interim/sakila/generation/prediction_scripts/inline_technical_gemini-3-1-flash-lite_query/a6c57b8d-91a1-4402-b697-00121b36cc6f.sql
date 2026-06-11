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
        c.h01 AS customer_id,
        co.c01 AS country_id,
        co.c02 AS country_name,
        ct.d02 AS city_name,
        mcs.payment_month,
        mcs.monthly_amount,
        mcs.payment_count,
        cya.avg_monthly_amount,
        PERCENT_RANK() OVER (PARTITION BY co.c01, mcs.payment_month ORDER BY mcs.monthly_amount DESC) AS country_percent_rank,
        RANK() OVER (PARTITION BY co.c01, mcs.payment_month ORDER BY mcs.monthly_amount DESC) AS country_rank
    FROM monthly_customer_stats mcs
    JOIN cus c ON c.h01 = mcs.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ct ON ct.d01 = a.e05
    JOIN cnt co ON co.c01 = ct.d03
    JOIN customer_yearly_avg cya ON cya.customer_id = mcs.customer_id
),
top_staff_per_month AS (
    SELECT customer_id, payment_month, staff_id
    FROM (
        SELECT p.p02 AS customer_id, strftime('%Y-%m', p.p06) AS payment_month, p.p03 AS staff_id,
               ROW_NUMBER() OVER (PARTITION BY p.p02, strftime('%Y-%m', p.p06) ORDER BY SUM(p.p05) DESC) as rn
        FROM pay p
        GROUP BY p.p02, strftime('%Y-%m', p.p06), p.p03
    ) WHERE rn = 1
)
SELECT
    cms.customer_id,
    cms.country_name,
    cms.city_name,
    cms.payment_month,
    ROUND(cms.monthly_amount, 2) AS monthly_amount,
    cms.payment_count,
    ROUND(cms.monthly_amount - cms.avg_monthly_amount, 2) AS deviation_from_avg,
    cms.country_rank,
    st.o02 AS staff_first_name,
    st.o03 AS staff_last_name
FROM country_monthly_stats cms
JOIN top_staff_per_month ts ON ts.customer_id = cms.customer_id AND ts.payment_month = cms.payment_month
JOIN stf st ON st.o01 = ts.staff_id
WHERE cms.monthly_amount > 2 * cms.avg_monthly_amount
  AND cms.country_percent_rank <= 0.10
ORDER BY cms.payment_month, cms.country_name, cms.country_rank;