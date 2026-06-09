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
    COUNT(p.p01) AS payment_count
  FROM pay p
  WHERE p.p06 >= '2004-11-01' AND p.p06 < '2006-01-01'
  GROUP BY p.p02, date(p.p06, 'start of month')
),
customer_stats AS (
  SELECT
    m.month_start,
    c.h01 AS customer_id,
    c.h02 AS store_id,
    ct.d02 AS city,
    cn.c02 AS country,
    COALESCE(ma.total_amount, 0) AS total_amount,
    COALESCE(ma.payment_count, 0) AS payment_count,
    AVG(ma.total_amount) OVER (
      PARTITION BY c.h01
      ORDER BY m.month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS prev_avg
  FROM months m
  CROSS JOIN cus c
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ct ON ct.d01 = a.e05
  JOIN cnt cn ON cn.c01 = ct.d03
  LEFT JOIN monthly_activity ma ON ma.customer_id = c.h01 AND ma.month_start = m.month_start
),
suspicious_months AS (
  SELECT *, (total_amount - prev_avg) AS deviation
  FROM customer_stats
  WHERE prev_avg > 0
    AND total_amount >= 2 * prev_avg
    AND payment_count >= 3
),
store_ranks AS (
  SELECT *,
    PERCENT_RANK() OVER (PARTITION BY store_id ORDER BY total_amount DESC) as p_rank
  FROM suspicious_months
),
top_clients AS (
  SELECT customer_id
  FROM store_ranks
  WHERE p_rank <= 0.1
  GROUP BY customer_id
  HAVING COUNT(*) = 12
),
staff_top AS (
  SELECT customer_id, month_start, staff_id, total_staff_amount,
    ROW_NUMBER() OVER (PARTITION BY customer_id, month_start ORDER BY total_staff_amount DESC) as rn
  FROM (
    SELECT p.p02 as customer_id, date(p.p06, 'start of month') as month_start, p.p03 as staff_id, SUM(p.p05) as total_staff_amount
    FROM pay p
    GROUP BY 1, 2, 3
  )
)
SELECT
  sm.store_id, sm.city, sm.country, sm.month_start, sm.total_amount, sm.payment_count,
  sm.deviation,
  RANK() OVER (PARTITION BY sm.store_id, sm.month_start ORDER BY sm.total_amount DESC) as store_rank,
  st.staff_id, s.o02 as staff_first_name, s.o03 as staff_last_name
FROM suspicious_months sm
JOIN top_clients tc ON sm.customer_id = tc.customer_id
JOIN staff_top st ON sm.customer_id = st.customer_id AND sm.month_start = st.month_start AND st.rn = 1
JOIN stf s ON st.staff_id = s.o01
ORDER BY sm.customer_id, sm.month_start;