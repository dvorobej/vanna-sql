WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month,
        SUM(p.p05) AS total_amount,
        COUNT(p.p01) AS payment_count,
        MAX(p.p03) AS top_staff_id -- Упрощенно: берем ID сотрудника, принявшего последний платеж в месяце
    FROM pay p
    WHERE strftime('%Y', p.p06) = '2005'
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
history_stats AS (
    SELECT
        ms.*,
        AVG(ms.total_amount) OVER (
            PARTITION BY ms.customer_id 
            ORDER BY ms.month 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount
    FROM monthly_stats ms
),
suspicious_months AS (
    SELECT
        hs.*,
        c.h02 AS store_id,
        ct.d02 AS city,
        cn.c02 AS country,
        RANK() OVER (PARTITION BY c.h02, hs.month ORDER BY hs.total_amount DESC) as rank_in_store,
        COUNT(*) OVER (PARTITION BY c.h02, hs.month) as store_month_total_clients
    FROM history_stats hs
    JOIN cus c ON c.h01 = hs.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ct ON ct.d01 = a.e05
    JOIN cnt cn ON cn.c01 = ct.d03
    WHERE hs.prev_avg_amount IS NOT NULL
      AND hs.total_amount >= 2 * hs.prev_avg_amount
      AND hs.payment_count >= 3
),
filtered_suspicious AS (
    SELECT *
    FROM suspicious_months
    WHERE rank_in_store <= (store_month_total_clients * 0.1)
)
SELECT
    fs.store_id,
    fs.country,
    fs.city,
    fs.month,
    fs.total_amount,
    fs.payment_count,
    ROUND(fs.total_amount / NULLIF(fs.prev_avg_amount, 0), 2) AS deviation_ratio,
    fs.rank_in_store,
    fs.top_staff_id
FROM filtered_suspicious fs
ORDER BY fs.month, fs.store_id, fs.rank_in_store;