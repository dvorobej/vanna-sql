WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS payment_count,
        MAX(p.p06) AS last_payment_date
    FROM pay AS p
    WHERE p.p06 BETWEEN '2005-01-01' AND '2005-12-31 23:59:59'
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_yearly_avg AS (
    SELECT
        customer_id,
        AVG(monthly_sum) AS avg_monthly_sum
    FROM monthly_stats
    GROUP BY customer_id
),
store_monthly_rank AS (
    SELECT
        ms.customer_id,
        ms.payment_month,
        ms.monthly_sum,
        ms.payment_count,
        c.h02 AS store_id,
        PERCENT_RANK() OVER (PARTITION BY c.h02, ms.payment_month ORDER BY ms.monthly_sum DESC) AS store_percent_rank
    FROM monthly_stats ms
    JOIN cus c ON ms.customer_id = c.h01
),
last_staff AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        p.p03 AS staff_id,
        ROW_NUMBER() OVER (PARTITION BY p.p02, strftime('%Y-%m', p.p06) ORDER BY p.p06 DESC) AS rn
    FROM pay p
)
SELECT
    ms.payment_month,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country,
    ct.d02 AS city,
    ms.monthly_sum,
    ms.payment_count,
    ROUND(ms.monthly_sum - cya.avg_monthly_sum, 2) AS deviation_from_avg,
    smr.store_percent_rank,
    stf.o02 || ' ' || stf.o03 AS last_staff_name
FROM monthly_stats ms
JOIN customer_yearly_avg cya ON ms.customer_id = cya.customer_id
JOIN store_monthly_rank smr ON ms.customer_id = smr.customer_id AND ms.payment_month = smr.payment_month
JOIN cus c ON ms.customer_id = c.h01
JOIN adr a ON c.h06 = a.e01
JOIN cty ct ON a.e05 = ct.d01
JOIN cnt cnt ON ct.d03 = cnt.c01
JOIN last_staff ls ON ms.customer_id = ls.customer_id AND ms.payment_month = ls.payment_month AND ls.rn = 1
JOIN stf stf ON ls.staff_id = stf.o01
WHERE ms.monthly_sum > cya.avg_monthly_sum
  AND smr.store_percent_rank <= 0.05
ORDER BY ms.payment_month, ms.monthly_sum DESC;