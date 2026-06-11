WITH
client_store_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS registration_store_id,
    ci.d02 AS city_name,
    cnt.c02 AS country_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = ci.d03
),
payments_2005 AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p05 AS payment_amount,
    date(p.p06, 'start of month') AS month_start,
    date(p.p06) AS payment_day
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
),
client_month AS (
  SELECT
    ps.customer_id,
    ps.month_start,
    COUNT(ps.payment_id) AS payment_count,
    SUM(ps.payment_amount) AS month_payment_sum
  FROM payments_2005 AS ps
  GROUP BY
    ps.customer_id,
    ps.month_start
),
client_year_avg AS (
  SELECT
    customer_id,
    AVG(month_payment_sum) AS personal_avg_monthly_sum
  FROM client_month
  GROUP BY customer_id
),
staff_last_in_month AS (
  SELECT
    ps.customer_id,
    ps.month_start,
    ps.staff_id AS last_staff_id,
    ROW_NUMBER() OVER (
      PARTITION BY ps.customer_id, ps.month_start
      ORDER BY ps.payment_id DESC
    ) AS rn
  FROM payments_2005 AS ps
),
client_rank_in_store_month AS (
  SELECT
    cm.customer_id,
    cm.month_start,
    cm.month_payment_sum,
    cm.payment_count,
    csg.registration_store_id,
    RANK() OVER (
      PARTITION BY csg.registration_store_id, cm.month_start
      ORDER BY cm.month_payment_sum DESC
    ) AS store_month_rank,
    SUM(1) OVER (
      PARTITION BY csg.registration_store_id, cm.month_start
    ) AS store_month_customer_count
  FROM client_month AS cm
  JOIN client_store_geo AS csg
    ON csg.customer_id = cm.customer_id
),
qualified_months AS (
  SELECT
    cr.customer_id,
    cr.month_start,
    cr.registration_store_id,
    csg.city_name,
    csg.country_name,
    cr.payment_count,
    cr.month_payment_sum,
    cy.personal_avg_monthly_sum,
    (cr.month_payment_sum - cy.personal_avg_monthly_sum) AS deviation_from_personal_avg,
    cr.store_month_rank,
    cr.store_month_customer_count
  FROM client_rank_in_store_month AS cr
  JOIN client_year_avg AS cy
    ON cy.customer_id = cr.customer_id
  JOIN client_store_geo AS csg
    ON csg.customer_id = cr.customer_id
  WHERE
    cy.personal_avg_monthly_sum > 0
    AND cr.month_payment_sum > cy.personal_avg_monthly_sum * 2
    AND cr.store_month_rank <= CAST(CEIL(cr.store_month_customer_count * 0.05) AS INT)
),
clients_all_months AS (
  SELECT
    customer_id
  FROM qualified_months
  GROUP BY customer_id
  HAVING COUNT(*) = 12
)
SELECT
  q.customer_id,
  q.registration_store_id AS store_id,
  q.city_name,
  q.country_name,
  strftime('%Y-%m', q.month_start) AS month,
  ROUND(q.month_payment_sum, 2) AS month_payment_sum,
  q.payment_count,
  ROUND(q.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
  q.store_month_rank AS store_month_rank,
  q.store_month_customer_count AS store_month_customer_count,
  ls.last_staff_id AS last_staff_id
FROM qualified_months AS q
JOIN clients_all_months AS cam
  ON cam.customer_id = q.customer_id
LEFT JOIN staff_last_in_month AS ls
  ON ls.customer_id = q.customer_id
 AND ls.month_start = q.month_start
 AND ls.rn = 1
ORDER BY
  q.customer_id,
  q.month_start;