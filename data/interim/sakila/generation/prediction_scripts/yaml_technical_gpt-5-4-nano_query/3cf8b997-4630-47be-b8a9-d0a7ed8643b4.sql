SELECT 12 AS expected_cnt
),
filtered AS (
  SELECT
    qcm.*
  FROM qualified_customers qcm
  JOIN expected_months em
    ON qcm.suspicious_months_cnt = em.expected_cnt
),
top_staff_by_month AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id,
    SUM(CAST(p.p05 AS REAL)) AS staff_total_amount,
    COUNT(*) AS staff_payment_count,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, date(p.p06, 'start of month')
      ORDER BY SUM(CAST(p.p05 AS REAL)) DESC, p.p03
    ) AS rn
  FROM pay p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06, 'start of month'),
    p.p03
)
SELECT
  tm.home_store_id AS store_id,
  ch.city_name AS city,
  ch.country_name AS country,
  strftime('%Y-%m', tm.month_start) AS month,
  ROUND(tm.month_total_amount, 2) AS month_payment_sum,
  tm.payment_count,
  ROUND(tm.deviation_from_rolling_avg, 2) AS deviation_from_rolling_avg,
  RANK() OVER (
    PARTITION BY tm.home_store_id, tm.month_start
    ORDER BY tm.month_total_amount DESC
  ) AS store_month_rank,
  st.o02 AS staff_first_name,
  st.o03 AS staff_last_name,
  ts.staff_id AS top_staff_id,
  ROUND(ts.staff_total_amount, 2) AS top_staff_total_amount
FROM top10_store_months tm
JOIN filtered f
  ON f.customer_id = tm.customer_id
 AND f.home_store_id = tm.home_store_id
JOIN customer_home ch
  ON ch.customer_id = tm.customer_id
LEFT JOIN top_staff_by_month ts
  ON ts.customer_id = tm.customer_id
 AND ts.month_start = tm.month_start
 AND ts.rn = 1
LEFT JOIN stf st
  ON st.o01 = ts.staff_id
ORDER BY
  tm.home_store_id,
  tm.month_start,
  tm.customer_id;