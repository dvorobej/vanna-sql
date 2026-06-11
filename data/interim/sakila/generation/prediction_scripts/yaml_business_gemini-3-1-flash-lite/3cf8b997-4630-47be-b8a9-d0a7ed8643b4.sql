WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS total_amount,
        COUNT(p.p01) AS payment_count,
        c.h02 AS store_id,
        ct.d02 AS city,
        cn.c02 AS country
    FROM pay p
    JOIN cus c ON c.h01 = p.p02
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ct ON ct.d01 = a.e05
    JOIN cnt cn ON cn.c01 = ct.d03
    WHERE p.p06 BETWEEN '2005-01-01' AND '2005-12-31'
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
history_stats AS (
    SELECT
        *,
        AVG(total_amount) OVER (
            PARTITION BY customer_id 
            ORDER BY payment_month 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount,
        COUNT(total_amount) OVER (
            PARTITION BY customer_id 
            ORDER BY payment_month 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS prev_months_count
    FROM monthly_stats
),
suspicious_months AS (
    SELECT
        *,
        (total_amount / NULLIF(prev_avg_amount, 0)) AS deviation_ratio,
        PERCENT_RANK() OVER (
            PARTITION BY store_id, payment_month 
            ORDER BY total_amount DESC
        ) AS store_rank_pct
    FROM history_stats
    WHERE prev_months_count = 2
      AND total_amount >= 2 * prev_avg_amount
      AND payment_count >= 3
),
top_staff AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        p.p03 AS staff_id,
        ROW_NUMBER() OVER (
            PARTITION BY p.p02, strftime('%Y-%m', p.p06) 
            ORDER BY SUM(p.p05) DESC
        ) AS rn
    FROM pay p
    GROUP BY p.p02, strftime('%Y-%m', p.p06), p.p03
)
SELECT
    sm.store_id,
    sm.country,
    sm.city,
    sm.payment_month,
    sm.customer_id,
    sm.total_amount,
    sm.payment_count,
    ROUND(sm.deviation_ratio, 2) AS deviation_from_avg,
    ts.staff_id AS top_staff_id
FROM suspicious_months sm
JOIN top_staff ts ON ts.customer_id = sm.customer_id 
                  AND ts.payment_month = sm.payment_month 
                  AND ts.rn = 1
WHERE sm.store_rank_pct <= 0.1
ORDER BY sm.payment_month, sm.store_id, sm.total_amount DESC;