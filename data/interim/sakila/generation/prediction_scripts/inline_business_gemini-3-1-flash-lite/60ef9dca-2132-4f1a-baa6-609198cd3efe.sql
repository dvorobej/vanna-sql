WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS payment_count,
        MAX(p.p03) AS last_staff_id
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
        ms.last_staff_id,
        c.h02 AS store_id,
        PERCENT_RANK() OVER (
            PARTITION BY c.h02, ms.payment_month 
            ORDER BY ms.monthly_sum DESC
        ) AS store_percent_rank
    FROM monthly_stats AS ms
    JOIN cus AS c ON ms.customer_id = c.h01
)
SELECT
    smr.payment_month,
    c.h03 || ' ' || c.h04 AS customer_name,
    co.c02 AS country,
    ct.d02 AS city,
    smr.store_id,
    smr.monthly_sum,
    smr.payment_count,
    ROUND(smr.monthly_sum - cya.avg_monthly_sum, 2) AS deviation_from_avg,
    smr.store_percent_rank,
    s.o02 || ' ' || s.o03 AS last_staff_name
FROM store_monthly_rank AS smr
JOIN customer_yearly_avg AS cya ON smr.customer_id = cya.customer_id
JOIN cus AS c ON smr.customer_id = c.h01
JOIN adr AS a ON c.h06 = a.e01
JOIN cty AS ct ON a.e05 = ct.d01
JOIN cnt AS co ON ct.d03 = co.c01
JOIN stf AS s ON smr.last_staff_id = s.o01
WHERE smr.monthly_sum > cya.avg_monthly_sum
  AND smr.store_percent_rank <= 0.05
ORDER BY smr.payment_month, smr.monthly_sum DESC;