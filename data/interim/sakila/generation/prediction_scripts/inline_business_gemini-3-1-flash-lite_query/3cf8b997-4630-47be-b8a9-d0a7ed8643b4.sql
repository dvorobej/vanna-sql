WITH RECURSIVE
months(month_start) AS (
  SELECT '2005-01-01'
  UNION ALL
  SELECT date(month_start, '+1 month')
  FROM months
  WHERE month_start < '2005-12-01'
),
customer_base AS (
  SELECT h01 AS customer_id, h02 AS store_id, h06 AS address_id FROM cus
),
monthly_activity AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(p.p05) AS payment_sum,
    COUNT(*) AS payment_count,
    MAX(p.p03) AS top_staff_id -- Placeholder for logic below
  FROM pay p
  WHERE p.p06 BETWEEN '2004-11-01' AND '2005-12-31'
  GROUP BY p.p02, date(p.p06, 'start of month')
),
rolling_stats AS (
  SELECT
    cb.customer_id,
    m.month_start,
    COALESCE(ma.payment_sum, 0) AS payment_sum,
    COALESCE(ma.payment_count, 0) AS payment_count,
    AVG(ma.payment_sum) OVER (
      PARTITION BY cb.customer_id
      ORDER BY m.month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS prev_avg_sum
  FROM customer_base cb
  CROSS JOIN months m
  LEFT JOIN monthly_activity ma ON ma.customer_id = cb.customer_id AND ma.month_start = m.month_start
),
suspicious_months AS (
  SELECT *, (payment_sum - prev_avg_sum) AS deviation
  FROM rolling_stats
  WHERE payment_sum >= 2 * prev_avg_sum AND payment_count >= 3
),
store_ranks AS (
  SELECT
    sm.*,
    cb.store_id,
    PERCENT_RANK() OVER (PARTITION BY cb.store_id, sm.month_start ORDER BY sm.payment_sum DESC) as p_rank
  FROM suspicious_months sm
  JOIN customer_base cb ON cb.customer_id = sm.customer_id
),
top_staff_per_month AS (
  SELECT customer_id, month_start, staff_id
  FROM (
    SELECT p.p02 as customer_id, date(p.p06, 'start of month') as month_start, p.p03 as staff_id,
           ROW_NUMBER() OVER (PARTITION BY p.p02, date(p.p06, 'start of month') ORDER BY SUM(p.p05) DESC) as rn
    FROM pay p GROUP BY 1, 2, 3
  ) WHERE rn = 1
)
SELECT
  sr.store_id,
  cty.d02 AS city,
  cnt.c02 AS country,
  sr.month_start,
  sr.payment_sum,
  sr.payment_count,
  sr.deviation,
  RANK() OVER (PARTITION BY sr.store_id, sr.month_start ORDER BY sr.payment_sum DESC) as store_rank,
  stf.o02 || ' ' || stf.o03 AS top_staff_name
FROM store_ranks sr
JOIN customer_base cb ON cb.customer_id = sr.customer_id
JOIN adr ON adr.e01 = cb.address_id
JOIN cty ON cty.d01 = adr.e05
JOIN cnt ON cnt.c01 = cty.d03
JOIN top_staff_per_month ts ON ts.customer_id = sr.customer_id AND ts.month_start = sr.month_start
JOIN stf ON stf.o01 = ts.staff_id
WHERE sr.p_rank <= 0.1
ORDER BY sr.month_start, sr.store_id, store_rank;