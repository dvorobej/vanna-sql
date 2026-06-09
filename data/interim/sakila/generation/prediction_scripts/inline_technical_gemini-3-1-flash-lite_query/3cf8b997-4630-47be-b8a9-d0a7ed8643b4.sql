WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS total_amount,
        COUNT(*) AS payment_count
    FROM pay AS p
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY p.p02, date(p.p06, 'start of month')
),
customer_stats AS (
    SELECT
        mp.*,
        AVG(mp.total_amount) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.month_start
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount,
        COUNT(mp.total_amount) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.month_start
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS prev_months_count
    FROM monthly_payments AS mp
),
suspicious_months AS (
    SELECT
        cs.*,
        c.h02 AS store_id,
        ct.d02 AS city,
        cn.c02 AS country
    FROM customer_stats AS cs
    JOIN cus AS c ON c.h01 = cs.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS cn ON cn.c01 = ct.d03
    WHERE cs.prev_months_count = 2
      AND cs.total_amount >= 2 * cs.prev_avg_amount
      AND cs.payment_count >= 3
),
store_ranks AS (
    SELECT
        sm.*,
        PERCENT_RANK() OVER (PARTITION BY sm.store_id ORDER BY sm.total_amount DESC) AS store_percentile,
        RANK() OVER (PARTITION BY sm.store_id, sm.month_start ORDER BY sm.total_amount DESC) AS store_rank
    FROM suspicious_months AS sm
),
top_staff AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        p.p03 AS staff_id,
        SUM(p.p05) AS staff_amount,
        ROW_NUMBER() OVER (PARTITION BY p.p02, date(p.p06, 'start of month') ORDER BY SUM(p.p05) DESC) AS rn
    FROM pay AS p
    GROUP BY p.p02, date(p.p06, 'start of month'), p.p03
)
SELECT
    sr.store_id,
    sr.city,
    sr.country,
    strftime('%Y-%m', sr.month_start) AS month,
    sr.total_amount,
    sr.payment_count,
    ROUND(sr.total_amount - sr.prev_avg_amount, 2) AS deviation,
    sr.store_rank,
    stf.o02 || ' ' || stf.o03 AS top_staff_name
FROM store_ranks AS sr
JOIN top_staff AS ts ON ts.customer_id = sr.customer_id AND ts.month_start = sr.month_start AND ts.rn = 1
JOIN stf ON stf.o01 = ts.staff_id
WHERE sr.store_percentile <= 0.1
ORDER BY sr.store_id, sr.month_start, sr.store_rank;