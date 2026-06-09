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
        ms.*,
        c.h02 AS store_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        ct.d02 AS city,
        cn.c02 AS country,
        cya.yearly_avg_monthly_sum,
        PERCENT_RANK() OVER (PARTITION BY c.h02, ms.payment_month ORDER BY ms.monthly_sum DESC) AS store_percent_rank,
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
        p.p03 AS staff_id
    FROM pay AS p
    JOIN (SELECT p02, strftime('%Y-%m', p06) AS m, MAX(p06) AS max_date FROM pay GROUP BY 1, 2) AS sub
      ON p.p02 = sub.p02 AND strftime('%Y-%m', p.p06) = sub.m AND p.p06 = sub.max_date
)
SELECT
    sr.customer_id,
    sr.customer_name,
    sr.store_id,
    sr.city,
    sr.country,
    sr.payment_month,
    sr.monthly_sum,
    sr.payment_count,
    ROUND(sr.monthly_sum - sr.yearly_avg_monthly_sum, 2) AS deviation_from_avg,
    sr.store_rank,
    ls.staff_id AS last_staff_id
FROM store_rankings AS sr
JOIN last_staff AS ls ON ls.customer_id = sr.customer_id AND ls.payment_month = sr.payment_month
WHERE sr.monthly_sum > 2 * sr.yearly_avg_monthly_sum
  AND sr.store_percent_rank <= 0.05
ORDER BY sr.payment_month, sr.store_id, sr.store_rank;