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
store_monthly_stats AS (
    SELECT
        c.h02 AS store_id,
        mcs.payment_month,
        mcs.monthly_sum,
        PERCENT_RANK() OVER (
            PARTITION BY c.h02, mcs.payment_month
            ORDER BY mcs.monthly_sum DESC
        ) AS monthly_rank_pct
    FROM monthly_customer_stats AS mcs
    JOIN cus AS c ON c.h01 = mcs.customer_id
),
last_staff_per_month AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        p.p03 AS last_staff_id
    FROM pay AS p
    WHERE (p.p02, p.p06) IN (
        SELECT p02, MAX(p06)
        FROM pay
        GROUP BY p02, strftime('%Y-%m', p06)
    )
),
monthly_analysis AS (
    SELECT
        mcs.*,
        c.h02 AS store_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cn.c02 AS country,
        ct.d02 AS city,
        cya.yearly_avg_monthly_sum,
        (mcs.monthly_sum - cya.yearly_avg_monthly_sum) AS deviation,
        sms.monthly_rank_pct,
        lsm.last_staff_id
    FROM monthly_customer_stats AS mcs
    JOIN cus AS c ON c.h01 = mcs.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS cn ON cn.c01 = ct.d03
    JOIN customer_yearly_avg AS cya ON cya.customer_id = mcs.customer_id
    JOIN store_monthly_stats AS sms ON sms.store_id = c.h02 AND sms.payment_month = mcs.payment_month AND sms.monthly_sum = mcs.monthly_sum
    JOIN last_staff_per_month AS lsm ON lsm.customer_id = mcs.customer_id AND lsm.payment_month = mcs.payment_month
)
SELECT *
FROM monthly_analysis
WHERE monthly_sum > (yearly_avg_monthly_sum * 2)
  AND monthly_rank_pct <= 0.05
  AND customer_id IN (
      SELECT customer_id
      FROM monthly_analysis
      GROUP BY customer_id
      HAVING COUNT(payment_month) = 12
  )
ORDER BY payment_month, store_id, monthly_sum DESC;