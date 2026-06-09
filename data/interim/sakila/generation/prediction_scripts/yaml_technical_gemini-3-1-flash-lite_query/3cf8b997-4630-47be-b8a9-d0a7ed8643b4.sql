WITH RECURSIVE
months(month_start) AS (
  SELECT '2005-01-01'
  UNION ALL
  SELECT date(month_start, '+1 month')
  FROM months
  WHERE month_start < '2005-12-01'
),
monthly_customer_stats AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(p.p05) AS total_amount,
    COUNT(p.p01) AS payment_count
  FROM pay p
  WHERE p.p06 >= '2004-11-01' AND p.p06 < '2006-01-01'
  GROUP BY p.p02, date(p.p06, 'start of month')
),
rolling_stats AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    ct.d02 AS city,
    cn.c02 AS country,
    m.month_start,
    COALESCE(mcs.total_amount, 0) AS total_amount,
    COALESCE(mcs.payment_count, 0) AS payment_count,
    AVG(mcs.total_amount) OVER (
      PARTITION BY c.h01 ORDER BY m.month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS prev_avg_amount
  FROM cus c
  CROSS JOIN months m
  LEFT JOIN monthly_customer_stats mcs ON mcs.customer_id = c.h01 AND mcs.month_start = m.month_start
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ct ON ct.d01 = a.e05
  JOIN cnt cn ON cn.c01 = ct.d03
),
suspicious_months AS (
  SELECT *, (total_amount - prev_avg_amount) AS deviation
  FROM rolling_stats
  WHERE prev_avg_amount > 0
    AND total_amount >= 2 * prev_avg_amount
    AND payment_count >= 3
),
store_rankings AS (
  SELECT *,
    PERCENT_RANK() OVER (PARTITION BY store_id, month_start ORDER BY total_amount DESC) as p_rank
  FROM suspicious_months
),
top_clients AS (
  SELECT customer_id
  FROM store_rankings
  WHERE p_rank <= 0.1
  GROUP BY customer_id
  HAVING COUNT(DISTINCT month_start) = 12
),
staff_monthly AS (
  SELECT p.p02 AS customer_id, date(p.p06, 'start of month') AS month_start, p.p03 AS staff_id,
         SUM(p.p05) AS staff_sum
  FROM pay p
  GROUP BY p.p02, date(p.p06, 'start of month'), p.p03
),
top_staff AS (
  SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY customer_id, month_start ORDER BY staff_sum DESC) as rn
    FROM staff_monthly
  ) WHERE rn = 1
)
SELECT
  sr.store_id, sr.city, sr.country, sr.month_start, sr.total_amount, sr.payment_count,
  sr.deviation,
  RANK() OVER (PARTITION BY sr.store_id, sr.month_start ORDER BY sr.total_amount DESC) as store_rank,
  st.staff_id, s.o02 || ' ' || s.o03 as staff_name
FROM store_rankings sr
JOIN top_clients tc ON sr.customer_id = tc.customer_id
JOIN top_staff st ON sr.customer_id = st.customer_id AND sr.month_start = st.month_start
JOIN stf s ON st.staff_id = s.o01
ORDER BY sr.customer_id, sr.month_start;