WITH monthly AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    co.c02 AS country_name,
    p.p04 AS rental_id,
    p.p03 AS staff_id,
    c.h02 AS customer_home_store_id,
    p.p02 AS customer_id_ref,
    strftime('%Y-%m', p.p06) AS month_start,
    COUNT(p.p01) AS payment_count,
    SUM(p.p05) AS payment_sum,
    AVG(p.p05) AS avg_check,
    COUNT(DISTINCT date(p.p06)) AS days_with_payments
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
  GROUP BY
    c.h01,
    c.h03,
    c.h04,
    co.c02,
    strftime('%Y-%m', p.p06),
    c.h02,
    p.p03
),
monthly_customer AS (
  SELECT
    m.customer_id,
    m.customer_name,
    m.country_name,
    m.month_start,
    SUM(m.payment_count) AS payment_count,
    SUM(m.payment_sum) AS payment_sum,
    AVG(m.avg_check) AS avg_check,
    MAX(m.days_with_payments) AS days_with_payments
  FROM monthly AS m
  GROUP BY
    m.customer_id,
    m.customer_name,
    m.country_name,
    m.month_start
),
with_prev AS (
  SELECT
    mc.*,
    LAG(mc.payment_sum) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
    ) AS prev_month_sum
  FROM monthly_customer AS mc
),
country_month_avg AS (
  SELECT
    month_start,
    country_name,
    AVG(payment_sum) AS country_avg_month_sum
  FROM with_prev
  GROUP BY month_start, country_name
),
country_month_ranks AS (
  SELECT
    wp.*,
    DENSE_RANK() OVER (
      PARTITION BY wp.country_name, wp.month_start
      ORDER BY wp.payment_sum DESC
    ) AS customer_country_rank
  FROM with_prev AS wp
),
top_staff AS (
  SELECT
    c.h01 AS customer_id,
    co.c02 AS country_name,
    strftime('%Y-%m', p.p06) AS month_start,
    p.p03 AS staff_id,
    SUM(p.p05) AS staff_payment_sum,
    ROW_NUMBER() OVER (
      PARTITION BY c.h01, co.c02, strftime('%Y-%m', p.p06)
      ORDER BY SUM(p.p05) DESC, p.p03
    ) AS rn
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
  GROUP BY
    c.h01,
    co.c02,
    strftime('%Y-%m', p.p06),
    p.p03
),
top_staff_resolved AS (
  SELECT
    ts.customer_id,
    ts.country_name,
    ts.month_start,
    ts.staff_id,
    s.o02 || ' ' || s.o03 AS staff_name,
    ts.staff_payment_sum AS top_staff_payment_sum
  FROM top_staff AS ts
  JOIN stf AS s
    ON s.o01 = ts.staff_id
  WHERE ts.rn = 1
)
SELECT
  cmr.month_start AS month,
  cmr.customer_id,
  cmr.customer_name,
  cmr.country_name AS country,
  c.h02 AS store_id,
  cmr.payment_count,
  ROUND(cmr.payment_sum, 2) AS payment_sum,
  ROUND(cmr.avg_check, 2) AS avg_check,
  cmr.days_with_payments,
  ROUND(cmr.prev_month_sum, 2) AS prev_month_sum,
  ROUND(cma.country_avg_month_sum, 2) AS country_avg_month_sum,
  cmr.customer_country_rank AS customer_country_rank,
  tsr.staff_name AS top_staff_name,
  ROUND(tsr.top_staff_payment_sum, 2) AS top_staff_payment_sum
FROM country_month_ranks AS cmr
JOIN country_month_avg AS cma
  ON cma.month_start = cmr.month_start
 AND cma.country_name = cmr.country_name
JOIN cus AS c
  ON c.h01 = cmr.customer_id
LEFT JOIN top_staff_resolved AS tsr
  ON tsr.customer_id = cmr.customer_id
 AND tsr.country_name = cmr.country_name
 AND tsr.month_start = cmr.month_start
WHERE
  (cmr.prev_month_sum IS NOT NULL AND cmr.payment_sum >= 3.0 * cmr.prev_month_sum)
  OR (cma.country_avg_month_sum > 0 AND cmr.payment_sum > 2.0 * cma.country_avg_month_sum)
ORDER BY
  cmr.month_start,
  cmr.country_name,
  cmr.customer_country_rank,
  cmr.payment_sum DESC,
  cmr.customer_id;