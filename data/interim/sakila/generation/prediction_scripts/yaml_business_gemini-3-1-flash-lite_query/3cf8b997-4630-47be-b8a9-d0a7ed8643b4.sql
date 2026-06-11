WITH RECURSIVE
months(month_start) AS (
  SELECT '2005-01-01'
  UNION ALL
  SELECT date(month_start, '+1 month')
  FROM months
  WHERE month_start < '2005-12-01'
),
monthly_activity AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(p.p05) AS total_amount,
    COUNT(*) AS payment_count
  FROM pay p
  WHERE p.p06 >= '2004-11-01' AND p.p06 < '2006-01-01'
  GROUP BY p.p02, date(p.p06, 'start of month')
),
customer_metrics AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    ct.d02 AS city,
    cn.c02 AS country,
    m.month_start,
    COALESCE(ma.total_amount, 0) AS total_amount,
    COALESCE(ma.payment_count, 0) AS payment_count,
    AVG(ma.total_amount) OVER (
      PARTITION BY c.h01 ORDER BY m.month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS rolling_avg
  FROM cus c
  CROSS JOIN months m
  LEFT JOIN monthly_activity ma ON ma.customer_id = c.h01 AND ma.month_start = m.month_start
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ct ON ct.d01 = a.e05
  JOIN cnt cn ON cn.c01 = ct.d03
),
suspicious_months AS (
  SELECT *, (total_amount - rolling_avg) AS deviation
  FROM customer_metrics
  WHERE rolling_avg > 0
    AND total_amount >= 2 * rolling_avg
    AND payment_count >= 3
),
store_rankings AS (
  SELECT *,
    PERCENT_RANK() OVER (PARTITION BY store_id, month_start ORDER BY total_amount DESC) as pr
  FROM suspicious_months
),
top_staff AS (
  SELECT customer_id, month_start, staff_id, total_staff_amount
  FROM (
    SELECT p.p02 as customer_id, date(p.p06, 'start of month') as month_start, p.p03 as staff_id,
           SUM(p.p05) as total_staff_amount,
           ROW_NUMBER() OVER (PARTITION BY p.p02, date(p.p06, 'start of month') ORDER BY SUM(p.p05) DESC) as rn
    FROM pay p
    GROUP BY 1, 2, 3
  ) WHERE rn = 1
)
SELECT
  sm.store_id, sm.city, sm.country, strftime('%Y-%m', sm.month_start) as month,
  sm.total_amount, sm.payment_count, sm.deviation,
  RANK() OVER (PARTITION BY sm.store_id, sm.month_start ORDER BY sm.total_amount DESC) as store_rank,
  ts.staff_id, s.o02 as staff_first_name, s.o03 as staff_last_name
FROM suspicious_months sm
JOIN store_rankings sr ON sm.customer_id = sr.customer_id AND sm.month_start = sr.month_start
JOIN top_staff ts ON sm.customer_id = ts.customer_id AND sm.month_start = ts.month_start
JOIN stf s ON ts.staff_id = s.o01
WHERE sr.pr <= 0.1
ORDER BY sm.month_start, sm.store_id, store_rank;