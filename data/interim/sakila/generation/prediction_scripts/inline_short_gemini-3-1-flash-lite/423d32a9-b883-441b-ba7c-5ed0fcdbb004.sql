WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month,
        SUM(p.p05) AS total_amount,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT st.o07) AS store_count
    FROM pay AS p
    JOIN stf AS st ON st.o01 = p.p03
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
history_stats AS (
    SELECT
        ms.*,
        (SELECT AVG(total_amount) 
         FROM pay AS p2 
         WHERE p2.p02 = ms.customer_id 
           AND strftime('%Y-%m', p2.p06) < ms.month) AS avg_prev_amount
    FROM monthly_stats AS ms
    WHERE ms.payment_count >= 5
      AND (ms.staff_count > 1 OR ms.store_count > 1)
),
filtered_customers AS (
    SELECT customer_id
    FROM history_stats
    WHERE total_amount >= 2 * COALESCE(avg_prev_amount, 0)
    GROUP BY customer_id
    HAVING COUNT(month) = 12
)
SELECT
    hs.month,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    hs.total_amount,
    hs.payment_count,
    ROUND(hs.total_amount - hs.avg_prev_amount, 2) AS deviation,
    RANK() OVER (PARTITION BY hs.month, cnt.c01 ORDER BY hs.total_amount DESC) AS country_rank
FROM history_stats AS hs
JOIN filtered_customers AS fc ON hs.customer_id = fc.customer_id
JOIN cus AS c ON c.h01 = hs.customer_id
JOIN adr AS a ON a.e01 = c.h06
JOIN cty ON cty.d01 = a.e05
JOIN cnt ON cnt.c01 = cty.d03
ORDER BY hs.month, country, country_rank;