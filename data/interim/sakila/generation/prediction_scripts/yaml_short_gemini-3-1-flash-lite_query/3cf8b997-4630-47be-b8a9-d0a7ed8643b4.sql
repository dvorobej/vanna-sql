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
    SUM(p.p05) AS payment_sum,
    COUNT(p.p01) AS payment_count,
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
    COALESCE(ma.payment_sum, 0) AS payment_sum,
    COALESCE(ma.payment_count, 0) AS payment_count,
    AVG(ma.payment_sum) OVER (
      PARTITION BY c.h01 ORDER BY m.month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS rolling_avg_2m
  FROM cus c
  CROSS JOIN months m
  LEFT JOIN monthly_activity ma ON ma.customer_id = c.h01 AND ma.month_start = m.month_start
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ct ON ct.d01 = a.e05
  JOIN cnt cn ON cn.c01 = ct.d03
),
filtered_suspicious AS (
  SELECT *,
    RANK() OVER (PARTITION BY store_id, month_start ORDER BY payment_sum DESC) as store_rank,
    COUNT(*) OVER (PARTITION BY store_id, month_start) as store_cust_count
  FROM customer_monthly_stats
  WHERE payment_count >= 3
    AND payment_sum >= 2 * rolling_avg_2m
),
top_staff_per_month AS (
  SELECT customer_id, month_start, staff_id
  FROM (
    SELECT p.p02 as customer_id, date(p.p06, 'start of month') as month_start, p.p03 as staff_id,
           ROW_NUMBER() OVER (PARTITION BY p.p02, date(p.p06, 'start of month') ORDER BY SUM(p.p05) DESC) as rn
    FROM pay p
    GROUP BY p.p02, date(p.p06, 'start of month'), p.p03
  ) WHERE rn = 1
)
SELECT
  fs.store_id, fs.city, fs.country, fs.month_start, fs.payment_sum, fs.payment_count,
  (fs.payment_sum - fs.rolling_avg_2m) as deviation, fs.store_rank,
  st.o02 || ' ' || st.o03 as staff_name
FROM filtered_suspicious fs
JOIN top_staff_per_month ts ON ts.customer_id = fs.customer_id AND ts.month_start = fs.month_start
JOIN stf st ON st.o01 = ts.staff_id
WHERE fs.store_rank <= (fs.store_cust_count * 0.1)
  AND NOT EXISTS (
    SELECT 1 FROM months m2
    WHERE NOT EXISTS (
      SELECT 1 FROM filtered_suspicious fs2
      WHERE fs2.customer_id = fs.customer_id AND fs2.month_start = m2.month_start
    )
  )
ORDER BY fs.customer_id, fs.month_start;