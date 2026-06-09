WITH monthly_stats AS (
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
    FROM monthly_stats
    GROUP BY customer_id
),
store_rankings AS (
    SELECT
        ms.customer_id,
        ms.payment_month,
        ms.monthly_sum,
        ms.payment_count,
        ms.last_payment_date,
        c.h02 AS store_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        ct.d02 AS city,
        cn.c02 AS country,
        cya.yearly_avg_monthly_sum,
        PERCENT_RANK() OVER (PARTITION BY c.h02, ms.payment_month ORDER BY ms.monthly_sum DESC) AS store_percentile,
        RANK() OVER (PARTITION BY c.h02, ms.payment_month ORDER BY ms.monthly_sum DESC) AS store_rank
    FROM monthly_stats AS ms
    JOIN cus AS c ON c.h01 = ms.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS cn ON cn.c01 = ct.d03
    JOIN customer_yearly_avg AS cya ON cya.customer_id = ms.customer_id
),
last_staff AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        p.p03 AS staff_id,
        ROW_NUMBER() OVER (PARTITION BY p.p02, strftime('%Y-%m', p.p06) ORDER BY p.p06 DESC) AS rn
    FROM pay AS p
)
SELECT
    sr.customer_name,
    sr.store_id,
    sr.city,
    sr.country,
    sr.payment_month,
    sr.monthly_sum,
    sr.payment_count,
    ROUND(sr.monthly_sum - sr.yearly_avg_monthly_sum, 2) AS deviation_from_avg,
    sr.store_rank,
    s.o02 || ' ' || s.o03 AS last_staff_name
FROM store_rankings AS sr
JOIN last_staff AS ls ON ls.customer_id = sr.customer_id AND ls.payment_month = sr.payment_month AND ls.rn = 1
JOIN stf AS s ON s.o01 = ls.staff_id
WHERE sr.monthly_sum > (sr.yearly_avg_monthly_sum * 2)
  AND sr.store_percentile <= 0.05
ORDER BY sr.payment_month, sr.store_id, sr.store_rank;