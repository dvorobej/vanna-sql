WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month,
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
            ORDER BY month 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount,
        COUNT(total_amount) OVER (
            PARTITION BY customer_id 
            ORDER BY month 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS prev_months_count
    FROM monthly_stats
),
suspicious_months AS (
    SELECT *, (total_amount / NULLIF(prev_avg_amount, 0)) AS ratio
    FROM history_stats
    WHERE prev_months_count = 2
      AND total_amount >= 2 * prev_avg_amount
      AND payment_count >= 3
),
store_ranks AS (
    SELECT *,
        PERCENT_RANK() OVER (PARTITION BY store_id, month ORDER BY total_amount DESC) AS store_percentile
    FROM suspicious_months
),
top_staff AS (
    SELECT customer_id, month, staff_id,
        ROW_NUMBER() OVER (PARTITION BY customer_id, month ORDER BY staff_sum DESC) as rn
    FROM (
        SELECT p.p02 AS customer_id, strftime('%Y-%m', p.p06) AS month, p.p03 AS staff_id, SUM(p.p05) AS staff_sum
        FROM pay p
        GROUP BY p.p02, strftime('%Y-%m', p.p06), p.p03
    )
)
SELECT
    sm.month,
    sm.customer_id,
    sm.store_id,
    sm.city,
    sm.country,
    sm.total_amount,
    sm.payment_count,
    ROUND(sm.ratio, 2) AS deviation_ratio,
    ts.staff_id AS top_staff_id
FROM store_ranks sm
JOIN top_staff ts ON ts.customer_id = sm.customer_id AND ts.month = sm.month AND ts.rn = 1
WHERE sm.store_percentile <= 0.1
ORDER BY sm.month, sm.store_id, sm.total_amount DESC;