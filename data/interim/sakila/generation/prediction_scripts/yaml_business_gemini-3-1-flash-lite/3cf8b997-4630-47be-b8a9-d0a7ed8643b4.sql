WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month,
        SUM(p.p05) AS total_amount,
        COUNT(p.p01) AS payment_count,
        c.h02 AS store_id,
        c.h06 AS address_id
    FROM pay p
    JOIN cus c ON c.h01 = p.p02
    WHERE p.p06 BETWEEN '2005-01-01' AND '2005-12-31 23:59:59'
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
history_stats AS (
    SELECT
        *,
        AVG(total_amount) OVER (
            PARTITION BY customer_id 
            ORDER BY month 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS prev_avg
    FROM monthly_stats
),
suspicious_months AS (
    SELECT
        *,
        (total_amount / NULLIF(prev_avg, 0)) AS ratio
    FROM history_stats
    WHERE prev_avg IS NOT NULL
      AND total_amount >= 2 * prev_avg
      AND payment_count >= 3
),
store_ranks AS (
    SELECT
        *,
        PERCENT_RANK() OVER (PARTITION BY store_id, month ORDER BY total_amount DESC) AS pr
    FROM suspicious_months
),
top_staff AS (
    SELECT customer_id, month, staff_id,
           ROW_NUMBER() OVER (PARTITION BY customer_id, month ORDER BY sum_amount DESC) as rn
    FROM (
        SELECT p.p02 as customer_id, strftime('%Y-%m', p.p06) as month, p.p03 as staff_id, SUM(p.p05) as sum_amount
        FROM pay p
        GROUP BY p.p02, strftime('%Y-%m', p.p06), p.p03
    )
)
SELECT
    sr.month,
    sr.customer_id,
    sr.store_id,
    ct.d02 AS city,
    cn.c02 AS country,
    sr.total_amount,
    sr.payment_count,
    sr.ratio AS deviation_ratio,
    RANK() OVER (PARTITION BY sr.store_id, sr.month ORDER BY sr.total_amount DESC) AS store_rank,
    ts.staff_id AS top_staff_id
FROM store_ranks sr
JOIN cus c ON c.h01 = sr.customer_id
JOIN adr a ON a.e01 = c.h06
JOIN cty ct ON ct.d01 = a.e05
JOIN cnt cn ON cn.c01 = ct.d03
JOIN top_staff ts ON ts.customer_id = sr.customer_id AND ts.month = sr.month AND ts.rn = 1
WHERE sr.pr <= 0.1
ORDER BY sr.month, sr.store_id, sr.total_amount DESC;