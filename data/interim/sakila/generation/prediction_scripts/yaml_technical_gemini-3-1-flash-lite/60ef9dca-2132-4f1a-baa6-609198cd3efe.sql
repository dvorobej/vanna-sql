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
monthly_details AS (
    SELECT
        mcs.*,
        c.h02 AS store_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cn.c02 AS country,
        ct.d02 AS city,
        cya.yearly_avg_monthly_sum,
        (SELECT p2.p03 FROM pay p2 
         WHERE p2.p02 = mcs.customer_id 
           AND strftime('%Y-%m', p2.p06) = mcs.payment_month 
         ORDER BY p2.p06 DESC LIMIT 1) AS last_staff_id,
        RANK() OVER (
            PARTITION BY c.h02, mcs.payment_month
            ORDER BY mcs.monthly_sum DESC
        ) AS store_rank
    FROM monthly_customer_stats AS mcs
    JOIN cus AS c ON c.h01 = mcs.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS cn ON cn.c01 = ct.d03
    JOIN customer_yearly_avg AS cya ON cya.customer_id = mcs.customer_id
    JOIN store_monthly_percentiles AS smp 
      ON smp.store_id = c.h02 
      AND smp.payment_month = mcs.payment_month 
      AND smp.monthly_sum = mcs.monthly_sum
    WHERE mcs.monthly_sum > (cya.yearly_avg_monthly_sum * 2)
      AND smp.percentile_rank <= 0.05
),
customer_monthly_counts AS (
    SELECT customer_id, COUNT(*) AS months_count
    FROM monthly_details
    GROUP BY customer_id
)
SELECT
    md.customer_id,
    md.customer_name,
    md.country,
    md.city,
    md.store_id,
    md.payment_month,
    ROUND(md.monthly_sum, 2) AS monthly_sum,
    md.payment_count,
    ROUND(md.yearly_avg_monthly_sum, 2) AS yearly_avg_monthly_sum,
    ROUND(md.monthly_sum - md.yearly_avg_monthly_sum, 2) AS deviation,
    md.store_rank,
    md.last_staff_id
FROM monthly_details AS md
JOIN customer_monthly_counts AS cmc ON cmc.customer_id = md.customer_id
WHERE cmc.months_count = 12
ORDER BY md.customer_id, md.payment_month;