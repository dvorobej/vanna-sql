WITH RECURSIVE
months(month_start) AS (
  SELECT '2005-01-01'
  UNION ALL
  SELECT date(month_start, '+1 month')
  FROM months
  WHERE month_start < '2005-12-01'
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
customer_monthly_data AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS full_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    cnt.c01 AS country_id,
    m.month_start,
    COALESCE(ms.total_amount, 0) AS total_amount,
    COALESCE(ms.payment_count, 0) AS payment_count,
    COALESCE(ms.staff_count, 0) AS staff_count,
    COALESCE(ms.store_count, 0) AS store_count,
    AVG(ms.total_amount) OVER (
      PARTITION BY c.h01
      ORDER BY m.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg
  FROM cus AS c
  CROSS JOIN months AS m
  LEFT JOIN monthly_stats AS ms ON ms.customer_id = c.h01 AND ms.month_start = m.month_start
  JOIN adr ON adr.e01 = c.h06
  JOIN cty ON cty.d01 = adr.e05
  JOIN cnt ON cnt.c01 = cty.d03
),
filtered_clients AS (
  SELECT
    cmd.*,
    (total_amount - prev_avg) AS deviation
  FROM customer_monthly_data AS cmd
  WHERE prev_avg IS NOT NULL
    AND total_amount >= 2 * prev_avg
    AND payment_count >= 5
    AND (staff_count > 1 OR store_count > 1)
),
ranked_clients AS (
  SELECT
    *,
    RANK() OVER (PARTITION BY country_id, month_start ORDER BY deviation DESC) AS country_rank
  FROM filtered_clients
)
SELECT
  strftime('%Y-%m', month_start) AS month,
  country,
  city,
  ROUND(total_amount, 2) AS total_amount,
  payment_count,
  ROUND(deviation, 2) AS deviation,
  country_rank
FROM ranked_clients
ORDER BY month_start, country, country_rank;