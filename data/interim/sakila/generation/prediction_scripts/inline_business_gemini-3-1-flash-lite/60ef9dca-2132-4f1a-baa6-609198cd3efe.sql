WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS payment_count,
        MAX(p.p03) AS last_staff_id
    FROM pay AS p
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
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
        c.h03, c.h04,
        a.e02 AS address,
        ct.d02 AS city,
        cn.c02 AS country,
        cya.avg_monthly_sum,
        PERCENT_RANK() OVER (PARTITION BY c.h02, ms.payment_month ORDER BY ms.monthly_sum DESC) AS store_percentile
    FROM monthly_stats ms
    JOIN customer_yearly_avg cya ON ms.customer_id = cya.customer_id
    JOIN cus c ON ms.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ct ON a.e05 = ct.d01
    JOIN cnt cn ON ct.d03 = cn.c01
)
SELECT
    payment_month,
    h03 || ' ' || h04 AS customer_name,
    country,
    city,
    address,
    store_id,
    monthly_sum,
    payment_count,
    (monthly_sum - avg_monthly_sum) AS deviation_from_avg,
    store_percentile,
    last_staff_id
FROM store_monthly_rank
WHERE monthly_sum > avg_monthly_sum
  AND store_percentile <= 0.05
ORDER BY payment_month, store_id, monthly_sum DESC;