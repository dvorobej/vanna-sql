WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS payment_count,
        MAX(p.p06) AS last_payment_date
    FROM pay AS p
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_yearly_avg AS (
    SELECT
        customer_id,
        AVG(monthly_sum) AS yearly_avg_monthly_sum
    FROM monthly_customer_stats
    GROUP BY customer_id
),
store_monthly_percentiles AS (
    SELECT
        c.h02 AS store_id,
        mcs.payment_month,
        mcs.monthly_sum,
        PERCENT_RANK() OVER (
            PARTITION BY c.h02, mcs.payment_month
            ORDER BY mcs.monthly_sum DESC
        ) AS percentile_rank
    FROM monthly_customer_stats AS mcs
    JOIN cus AS c ON c.h01 = mcs.customer_id
),
last_staff_per_month AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        p.p03 AS staff_id,
        ROW_NUMBER() OVER (
            PARTITION BY p.p02, strftime('%Y-%m', p.p06)
            ORDER BY p.p06 DESC
        ) AS rn
    FROM pay AS p
)
SELECT
    mcs.payment_month,
    mcs.customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    c.h02 AS store_id,
    ROUND(mcs.monthly_sum, 2) AS monthly_sum,
    mcs.payment_count,
    ROUND(mcs.monthly_sum - cya.yearly_avg_monthly_sum, 2) AS deviation_from_avg,
    lsm.staff_id AS last_staff_id
FROM monthly_customer_stats AS mcs
JOIN cus AS c ON c.h01 = mcs.customer_id
JOIN adr ON adr.e01 = c.h06
JOIN cty ON cty.d01 = adr.e05
JOIN cnt ON cnt.c01 = cty.d03
JOIN customer_yearly_avg AS cya ON cya.customer_id = mcs.customer_id
JOIN store_monthly_percentiles AS smp 
    ON smp.store_id = c.h02 
    AND smp.payment_month = mcs.payment_month 
    AND smp.monthly_sum = mcs.monthly_sum
JOIN last_staff_per_month AS lsm 
    ON lsm.customer_id = mcs.customer_id 
    AND lsm.payment_month = mcs.payment_month 
    AND lsm.rn = 1
WHERE mcs.monthly_sum > (cya.yearly_avg_monthly_sum * 2)
  AND smp.percentile_rank <= 0.05
GROUP BY mcs.customer_id
HAVING COUNT(mcs.payment_month) = 12
ORDER BY mcs.customer_id, mcs.payment_month;