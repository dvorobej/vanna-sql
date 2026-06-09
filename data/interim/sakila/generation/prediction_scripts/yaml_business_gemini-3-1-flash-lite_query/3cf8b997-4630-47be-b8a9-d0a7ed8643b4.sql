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
    COUNT(*) AS payment_count,
    MAX(p.p03) AS top_staff_id -- Placeholder for logic below
  FROM pay p
  WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
  GROUP BY p.p02, date(p.p06, 'start of month')
),
customer_monthly_stats AS (
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
    ) AS prev_avg_amount,
    COUNT(ma.total_amount) OVER (
      PARTITION BY c.h01 ORDER BY m.month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS prev_months_count
  FROM cus c
  CROSS JOIN months m
  LEFT JOIN monthly_activity ma ON ma.customer_id = c.h01 AND ma.month_start = m.month_start
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ct ON ct.d01 = a.e05
  JOIN cnt cn ON cn.c01 = ct.d03
),
suspicious_months AS (
  SELECT *, (total_amount - prev_avg_amount) AS deviation
  FROM customer_monthly_stats
  WHERE prev_months_count = 2
    AND total_amount >= 2 * prev_avg_amount
    AND payment_count >= 3
),
store_rankings AS (
  SELECT *,
    PERCENT_RANK() OVER (PARTITION BY store_id, month_start ORDER BY total_amount DESC) as p_rank
  FROM suspicious_months
),
top_staff_per_month AS (
  SELECT customer_id, month_start, staff_id
  FROM (
    SELECT p.p02 AS customer_id, date(p.p06, 'start of month') AS month_start, p.p03 AS staff_id,
           SUM(p.p05) as s_amt,
           ROW_NUMBER() OVER (PARTITION BY p.p02, date(p.p06, 'start of month') ORDER BY SUM(p.p05) DESC) as rn
    FROM pay p
    GROUP BY 1, 2, 3
  ) WHERE rn = 1
)
SELECT
  sm.store_id, sm.city, sm.country, sm.month_start, sm.total_amount, sm.payment_count,
  sm.deviation,
  RANK() OVER (PARTITION BY sm.store_id, sm.month_start ORDER BY sm.total_amount DESC) as store_rank,
  st.o02 || ' ' || st.o03 as top_staff_name
FROM store_rankings sm
JOIN top_staff_per_month ts ON ts.customer_id = sm.customer_id AND ts.month_start = sm.month_start
JOIN stf st ON st.o01 = ts.staff_id
WHERE sm.p_rank <= 0.1
ORDER BY sm.month_start, sm.store_id, store_rank;