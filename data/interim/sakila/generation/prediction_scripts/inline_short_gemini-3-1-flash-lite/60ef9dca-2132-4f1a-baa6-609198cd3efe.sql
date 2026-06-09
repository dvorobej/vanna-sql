WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS total_amount,
        COUNT(p.p01) AS payment_count,
        MAX(p.p06) AS last_payment_date,
        (SELECT p3.p03 FROM pay p3 WHERE p3.p02 = p.p02 AND p3.p06 = MAX(p.p06)) AS last_staff_id
    FROM pay p
    WHERE strftime('%Y', p.p06) = '2005'
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
        PERCENT_RANK() OVER (PARTITION BY c.h02, ms.payment_month ORDER BY ms.total_amount DESC) AS store_rank_pct
    FROM monthly_stats ms
    JOIN cus c ON ms.customer_id = c.h01
    JOIN customer_yearly_avg cya ON ms.customer_id = cya.customer_id
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ct ON a.e05 = ct.d01
    JOIN cnt cn ON ct.d03 = cn.c01
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
    store_rank_pct,
    last_staff_id
FROM ranked_monthly
WHERE total_amount > (avg_monthly_amount * 2)
  AND store_rank_pct <= 0.05
ORDER BY payment_month, store_id, total_amount DESC;