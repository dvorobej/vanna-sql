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
        AVG(monthly_sum) AS yearly_avg_monthly_sum
    FROM monthly_stats
    GROUP BY customer_id
),
store_monthly_rankings AS (
    SELECT
        ms.customer_id,
        ms.payment_month,
        ms.monthly_sum,
        ms.payment_count,
        ms.last_payment_date,
        c.h02 AS store_id,
        c.h03, c.h04,
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
    JOIN (SELECT p02, strftime('%Y-%m', p06) AS m, MAX(p06) AS max_d FROM pay GROUP BY 1, 2) AS latest
      ON p.p02 = latest.p02 AND strftime('%Y-%m', p.p06) = latest.m AND p.p06 = latest.max_d
)
SELECT
    smr.customer_id,
    smr.h03 || ' ' || smr.h04 AS customer_name,
    smr.store_id,
    smr.city,
    smr.country,
    smr.payment_month,
    smr.monthly_sum,
    smr.payment_count,
    ROUND(smr.monthly_sum - smr.yearly_avg_monthly_sum, 2) AS deviation_from_avg,
    smr.store_rank,
    ls.staff_id AS last_staff_id
FROM store_monthly_rankings AS smr
JOIN last_staff AS ls ON ls.customer_id = smr.customer_id AND ls.payment_month = smr.payment_month
WHERE smr.monthly_sum > (2 * smr.yearly_avg_monthly_sum)
  AND smr.store_percent_rank <= 0.05
GROUP BY smr.customer_id
HAVING COUNT(smr.payment_month) = 12
ORDER BY smr.payment_month, smr.store_rank;