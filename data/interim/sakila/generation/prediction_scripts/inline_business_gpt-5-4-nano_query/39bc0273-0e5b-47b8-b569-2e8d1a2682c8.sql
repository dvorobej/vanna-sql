WITH monthly_customer AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS customer_first_name,
    c.h04 AS customer_last_name,
    c.h02 AS customer_home_store_id,
    co.c02 AS country_name,
    strftime('%Y-%m', p.p06) AS month_start,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS monthly_sum,
    AVG(p.p05) AS avg_check,
    COUNT(DISTINCT date(p.p06)) AS days_with_payments
  FROM pay AS p
  JOIN cus AS c ON c.h01 = p.p02
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ct ON ct.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ct.d03
  GROUP BY
    c.h01, c.h03, c.h04, c.h02, co.c02, strftime('%Y-%m', p.p06)
),
monthly_with_history AS (
  SELECT
    mc.*,
    LAG(mc.monthly_sum) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
    ) AS prev_month_sum
  FROM monthly_customer AS mc
),
country_monthly_avg AS (
  SELECT
    mwh.country_name,
    mwh.month_start,
    AVG(mwh.monthly_sum) AS country_avg_monthly_sum
  FROM monthly_with_history AS mwh
  GROUP BY mwh.country_name, mwh.month_start
),
ranked AS (
  SELECT
    mwh.*,
    cma.country_avg_monthly_sum,
    DENSE_RANK() OVER (
      PARTITION BY mwh.country_name, mwh.month_start
      ORDER BY mwh.monthly_sum DESC
    ) AS customer_country_amount_rank
  FROM monthly_with_history AS mwh
  JOIN country_monthly_avg AS cma
    ON cma.country_name = mwh.country_name
   AND cma.month_start = mwh.month_start
),
top_staff_per_customer_month AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS month_start,
    p.p03 AS staff_id,
    SUM(p.p05) AS staff_month_sum,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, strftime('%Y-%m', p.p06)
      ORDER BY SUM(p.p05) DESC, p.p03
    ) AS rn
  FROM pay AS p
  GROUP BY p.p02, strftime('%Y-%m', p.p06), p.p03
)
SELECT
  r.customer_id,
  r.customer_first_name,
  r.customer_last_name,
  r.country_name AS country,
  r.customer_home_store_id AS store_id,
  r.month_start AS month,
  r.payment_count,
  ROUND(r.monthly_sum, 2) AS monthly_sum,
  ROUND(r.avg_check, 2) AS avg_check,
  r.days_with_payments AS days_with_payments,
  ROUND(r.country_avg_monthly_sum, 2) AS country_avg_monthly_sum,
  ROUND(r.prev_month_sum, 2) AS prev_month_sum,
  r.customer_country_amount_rank AS customer_country_amount_rank,
  ts.staff_id,
  s.o02 AS staff_first_name,
  s.o03 AS staff_last_name,
  ROUND(ts.staff_month_sum, 2) AS top_staff_month_sum
FROM ranked AS r
LEFT JOIN top_staff_per_customer_month AS ts
  ON ts.customer_id = r.customer_id
 AND ts.month_start = r.month_start
 AND ts.rn = 1
LEFT JOIN stf AS s
  ON s.o01 = ts.staff_id
WHERE
  (r.prev_month_sum IS NOT NULL AND r.monthly_sum >= 3.0 * r.prev_month_sum)
  OR (r.monthly_sum > 2.0 * r.country_avg_monthly_sum)
ORDER BY
  r.country_name,
  r.month_start,
  r.customer_country_amount_rank,
  r.customer_id;