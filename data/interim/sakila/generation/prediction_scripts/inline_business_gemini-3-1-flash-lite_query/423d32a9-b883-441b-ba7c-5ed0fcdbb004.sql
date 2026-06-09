WITH RECURSIVE
months(month_start) AS (
  SELECT '2005-01-01'
  UNION ALL
  SELECT date(month_start, '+1 month')
  FROM months
  WHERE month_start < '2005-12-01'
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS full_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    cnt.c01 AS country_id
  FROM cus AS c
  JOIN adr ON adr.e01 = c.h06
  JOIN cty ON cty.d01 = adr.e05
  JOIN cnt ON cnt.c01 = cty.d03
),
monthly_stats AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(p.p05) AS total_amount,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT stf.o07) AS store_count
  FROM pay AS p
  JOIN stf ON stf.o01 = p.p03
  WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
  GROUP BY p.p02, date(p.p06, 'start of month')
),
history_stats AS (
  SELECT
    cg.customer_id,
    m.month_start,
    COALESCE(ms.total_amount, 0) AS total_amount,
    COALESCE(ms.payment_count, 0) AS payment_count,
    COALESCE(ms.staff_count, 0) AS staff_count,
    COALESCE(ms.store_count, 0) AS store_count,
    AVG(ms.total_amount) OVER (
      PARTITION BY cg.customer_id
      ORDER BY m.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg
  FROM customer_geo AS cg
  CROSS JOIN months AS m
  LEFT JOIN monthly_stats AS ms ON ms.customer_id = cg.customer_id AND ms.month_start = m.month_start
),
filtered_customers AS (
  SELECT customer_id
  FROM history_stats
  WHERE prev_avg IS NOT NULL
  GROUP BY customer_id
  HAVING SUM(CASE 
    WHEN total_amount >= 2 * prev_avg 
         AND payment_count >= 5 
         AND (staff_count > 1 OR store_count > 1) 
    THEN 1 ELSE 0 END) = 12
)
SELECT
  strftime('%Y-%m', hs.month_start) AS month,
  cg.country,
  cg.city,
  hs.total_amount,
  hs.payment_count,
  ROUND(hs.total_amount - hs.prev_avg, 2) AS deviation,
  RANK() OVER (
    PARTITION BY cg.country_id, hs.month_start
    ORDER BY (hs.total_amount - hs.prev_avg) DESC
  ) AS country_rank
FROM history_stats AS hs
JOIN customer_geo AS cg ON cg.customer_id = hs.customer_id
WHERE hs.customer_id IN (SELECT customer_id FROM filtered_customers)
ORDER BY hs.month_start, country_rank;