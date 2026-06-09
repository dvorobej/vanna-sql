WITH RECURSIVE
months(month_start) AS (
  SELECT '2005-01-01'
  UNION ALL
  SELECT date(month_start, '+1 month')
  FROM months
  WHERE month_start < '2005-12-01'
),
customer_monthly_stats AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(p.p05) AS total_amount,
    COUNT(p.p01) AS payment_count,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT stf.o07) AS store_count
  FROM pay AS p
  JOIN stf ON stf.o01 = p.p03
  GROUP BY p.p02, date(p.p06, 'start of month')
),
customer_history AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    cnt.c01 AS country_id,
    m.month_start,
    COALESCE(cms.total_amount, 0) AS total_amount,
    COALESCE(cms.payment_count, 0) AS payment_count,
    COALESCE(cms.staff_count, 0) AS staff_count,
    COALESCE(cms.store_count, 0) AS store_count,
    AVG(cms.total_amount) OVER (
      PARTITION BY c.h01
      ORDER BY m.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_amount
  FROM cus AS c
  CROSS JOIN months AS m
  LEFT JOIN customer_monthly_stats AS cms
    ON cms.customer_id = c.h01 AND cms.month_start = m.month_start
  JOIN adr ON adr.e01 = c.h06
  JOIN cty ON cty.d01 = adr.e05
  JOIN cnt ON cnt.c01 = cty.d03
),
filtered_customers AS (
  SELECT customer_id
  FROM customer_history
  WHERE month_start BETWEEN '2005-01-01' AND '2005-12-01'
  GROUP BY customer_id
  HAVING SUM(
    CASE
      WHEN total_amount >= 2 * COALESCE(prev_avg_amount, 0)
           AND payment_count >= 5
           AND (staff_count >= 2 OR store_count >= 2)
      THEN 1 ELSE 0
    END
  ) = 12
)
SELECT
  strftime('%Y-%m', ch.month_start) AS month,
  ch.country,
  ch.city,
  ch.total_amount,
  ch.payment_count,
  ROUND(ch.total_amount - ch.prev_avg_amount, 2) AS deviation_from_avg,
  RANK() OVER (
    PARTITION BY ch.country_id, ch.month_start
    ORDER BY ch.total_amount DESC
  ) AS country_rank
FROM customer_history AS ch
JOIN filtered_customers AS fc ON fc.customer_id = ch.customer_id
WHERE ch.month_start BETWEEN '2005-01-01' AND '2005-12-01'
ORDER BY ch.month_start, ch.country, country_rank;