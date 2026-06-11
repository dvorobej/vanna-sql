WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS total_amount,
        COUNT(p.p01) AS payment_count,
        MAX(p.p03) AS last_staff_id
    FROM pay AS p
    WHERE p.p06 BETWEEN '2005-01-01' AND '2005-12-31 23:59:59'
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_yearly_avg AS (
    SELECT
        customer_id,
        AVG(total_amount) AS avg_monthly_amount
    FROM monthly_stats
    GROUP BY customer_id
),
ranked_monthly AS (
    SELECT
        ms.*,
        c.h02 AS store_id,
        ct.d02 AS city,
        cn.c02 AS country,
        c.h03 || ' ' || c.h04 AS customer_name,
        cya.avg_monthly_amount,
        PERCENT_RANK() OVER (
            PARTITION BY c.h02, ms.payment_month 
            ORDER BY ms.total_amount DESC
        ) AS store_rank_percentile
    FROM monthly_stats AS ms
    JOIN cus AS c ON ms.customer_id = c.h01
    JOIN customer_yearly_avg AS cya ON ms.customer_id = cya.customer_id
    JOIN adr AS a ON c.h06 = a.e01
    JOIN cty AS ct ON a.e05 = ct.d01
    JOIN cnt AS cn ON ct.d03 = cn.c01
)
SELECT
    customer_name,
    store_id,
    city,
    country,
    payment_month,
    total_amount,
    payment_count,
    ROUND(total_amount - avg_monthly_amount, 2) AS deviation_from_avg,
    ROUND(store_rank_percentile, 4) AS rank_percentile,
    last_staff_id
FROM ranked_monthly
WHERE total_amount > (avg_monthly_amount * 2)
  AND store_rank_percentile <= 0.05
ORDER BY payment_month, store_id, total_amount DESC;