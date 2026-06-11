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
    c.h03 AS first_name,
    c.h04 AS last_name,
    cn.c02 AS country,
    ci.d02 AS city
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS cn ON cn.c01 = ci.d03
),
monthly_payments AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(p.p01) AS payment_count,
    SUM(p.p05) AS payment_sum,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT s.o07) AS distinct_store_count
  FROM pay AS p
  LEFT JOIN stf AS s ON s.o01 = p.p03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
monthly_full AS (
  SELECT
    cg.customer_id,
    cg.first_name,
    cg.last_name,
    cg.country,
    cg.city,
    m.month_start,
    COALESCE(mp.payment_count, 0) AS payment_count,
    COALESCE(mp.payment_sum, 0.0) AS payment_sum,
    COALESCE(mp.distinct_staff_count, 0) AS distinct_staff_count,
    COALESCE(mp.distinct_store_count, 0) AS distinct_store_count
  FROM customer_geo AS cg
  CROSS JOIN months AS m
  LEFT JOIN monthly_payments AS mp
    ON mp.customer_id = cg.customer_id
   AND mp.month_start = m.month_start
),
monthly_with_avgs AS (
  SELECT
    mf.*,
    AVG(mf.payment_sum) OVER (
      PARTITION BY mf.customer_id
      ORDER BY mf.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_monthly_sum
  FROM monthly_full AS mf
),
qualifying_months AS (
  SELECT
    mw.*,
    (mw.payment_sum - mw.prev_avg_monthly_sum) AS deviation_from_prev_avg,
    RANK() OVER (
      PARTITION BY mw.country
      ORDER BY (mw.payment_sum - mw.prev_avg_monthly_sum) DESC
    ) AS country_deviation_rank
  FROM monthly_with_avgs AS mw
  WHERE mw.prev_avg_monthly_sum IS NOT NULL
    AND mw.payment_count >= 5
    AND mw.payment_sum >= 2.0 * mw.prev_avg_monthly_sum
    AND (
      mw.distinct_staff_count >= 2
      OR mw.distinct_store_count >= 2
    )
),
qualifying_customers AS (
  SELECT
    customer_id
  FROM qualifying_months
  GROUP BY customer_id
  HAVING COUNT(*) = 11
)
SELECT
  qm.customer_id,
  qm.first_name,
  qm.last_name,
  qm.country,
  qm.city,
  strftime('%Y-%m', qm.month_start) AS payment_month,
  ROUND(qm.payment_sum, 2) AS payment_sum,
  qm.payment_count,
  ROUND(qm.deviation_from_prev_avg, 2) AS deviation_from_prev_avg,
  qm.country_deviation_rank
FROM qualifying_months AS qm
JOIN qualifying_customers AS qc
  ON qc.customer_id = qm.customer_id
ORDER BY
  qm.customer_id,
  qm.month_start;