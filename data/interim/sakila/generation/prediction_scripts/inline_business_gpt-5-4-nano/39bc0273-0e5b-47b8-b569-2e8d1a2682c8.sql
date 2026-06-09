WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS customer_first_name,
    c.h04 AS customer_last_name,
    c.h02 AS registration_store_id,
    ci.d02 AS city_name,
    co.c02 AS country_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ci.d03
),
base_payments AS (
  SELECT
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    s.o07 AS staff_store_id,
    date(p.p06, 'start of month') AS month_start,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p01 AS payment_id
  FROM pay AS p
  JOIN stf AS s ON s.o01 = p.p03
),
monthly_customer AS (
  SELECT
    bp.customer_id,
    cg.customer_first_name,
    cg.customer_last_name,
    cg.registration_store_id,
    cg.city_name,
    cg.country_name,
    bp.month_start,
    COUNT(bp.payment_id) AS payment_count,
    SUM(bp.payment_amount) AS monthly_amount,
    AVG(bp.payment_amount) AS avg_check,
    SUM(CASE WHEN date((SELECT p2.p06 FROM pay p2 WHERE p2.p01 = bp.payment_id)) > bp.month_start THEN 0 ELSE 0 END) AS dummy
  FROM base_payments AS bp
  JOIN customer_geo AS cg ON cg.customer_id = bp.customer_id
  GROUP BY
    bp.customer_id,
    cg.customer_first_name,
    cg.customer_last_name,
    cg.registration_store_id,
    cg.city_name,
    cg.country_name,
    bp.month_start
),
monthly_with_prev AS (
  SELECT
    mc.*,
    LAG(monthly_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
    ) AS prev_month_amount
  FROM monthly_customer AS mc
),
country_month_avg AS (
  SELECT
    month_start,
    customer_geo.country_name,
    AVG(monthly_amount) AS country_avg_monthly_amount
  FROM monthly_customer AS monthly_customer
  JOIN customer_geo ON customer_geo.customer_id = monthly_customer.customer_id
  GROUP BY
    month_start,
    customer_geo.country_name
),
country_rank AS (
  SELECT
    mc.*,
    DENSE_RANK() OVER (
      PARTITION BY mc.country_name, mc.month_start
      ORDER BY mc.monthly_amount DESC
    ) AS country_month_amount_rank
  FROM monthly_customer AS mc
),
staff_top_store AS (
  SELECT
    mc.customer_id,
    mc.month_start,
    p.staff_id,
    COUNT(*) AS staff_payment_count,
    SUM(p.payment_amount) AS staff_payment_amount,
    ROW_NUMBER() OVER (
      PARTITION BY mc.customer_id, mc.month_start
      ORDER BY COUNT(*) DESC, SUM(p.payment_amount) DESC, p.staff_id
    ) AS rn
  FROM (
    SELECT
      p.p02 AS customer_id,
      date(p.p06, 'start of month') AS month_start,
      p.p03 AS staff_id,
      p.p01 AS payment_id,
      CAST(p.p05 AS REAL) AS payment_amount
    FROM pay AS p
  ) AS p
  JOIN monthly_customer AS mc
    ON mc.customer_id = p.customer_id
   AND mc.month_start = p.month_start
  GROUP BY
    mc.customer_id,
    mc.month_start,
    p.staff_id
)
SELECT
  cm.customer_id,
  cm.customer_first_name,
  cm.customer_last_name,
  cm.country_name,
  cm.city_name,
  cm.registration_store_id,
  cm.month_start AS payment_month,
  cm.payment_count,
  ROUND(cm.monthly_amount, 2) AS monthly_amount,
  ROUND(cm.avg_check, 2) AS avg_check,
  ROUND(cm.monthly_amount - cm.prev_month_amount, 2) AS delta_from_prev_month,
  CASE
    WHEN cm.prev_month_amount IS NULL OR cm.prev_month_amount = 0 THEN NULL
    ELSE ROUND(cm.monthly_amount / cm.prev_month_amount, 3)
  END AS ratio_to_prev_month,
  cma.country_avg_monthly_amount,
  CASE
    WHEN cma.country_avg_monthly_amount IS NULL OR cma.country_avg_monthly_amount = 0 THEN NULL
    ELSE ROUND(cm.monthly_amount / cma.country_avg_monthly_amount, 3)
  END AS ratio_to_country_avg,
  cr.country_month_amount_rank,
  st.staff_id AS top_staff_id,
  s.o02 || ' ' || s.o03 AS top_staff_name,
  st.staff_payment_count AS top_staff_payment_count,
  st.staff_payment_amount AS top_staff_payment_amount
FROM monthly_with_prev AS cm
JOIN country_month_avg AS cma
  ON cma.month_start = cm.month_start
 AND cma.country_name = cm.country_name
JOIN country_rank AS cr
  ON cr.customer_id = cm.customer_id
 AND cr.month_start = cm.month_start
 AND cr.country_name = cm.country_name
LEFT JOIN staff_top_store AS st
  ON st.customer_id = cm.customer_id
 AND st.month_start = cm.month_start
 AND st.rn = 1
LEFT JOIN stf AS s
  ON s.o01 = st.staff_id
WHERE
  (cm.prev_month_amount IS NOT NULL AND cm.prev_month_amount > 0 AND cm.monthly_amount >= 2.0 * cm.prev_month_amount)
  OR (cma.country_avg_monthly_amount IS NOT NULL AND cma.country_avg_monthly_amount > 0 AND cm.monthly_amount >= 1.5 * cma.country_avg_monthly_amount)
ORDER BY
  cm.month_start,
  cm.country_name,
  cr.country_month_amount_rank,
  cm.monthly_amount DESC,
  cm.customer_id;