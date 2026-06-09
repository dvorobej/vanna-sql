WITH base AS (
  SELECT
    p.p02 AS customer_id,
    c.h03 AS customer_first_name,
    c.h04 AS customer_last_name,
    c.h02 AS customer_home_store_id,
    cn.c02 AS country_name,
    date(p.p06, 'start of month') AS month_start,
    p.p01 AS payment_id,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p03 AS staff_id,
    stf.o07 AS staff_store_id
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS cn
    ON cn.c01 = ci.d03
  LEFT JOIN stf
    ON stf.o01 = p.p03
),
monthly AS (
  SELECT
    customer_id,
    customer_first_name,
    customer_last_name,
    country_name,
    month_start,
    COUNT(payment_id) AS payment_count,
    SUM(payment_amount) AS monthly_amount,
    AVG(payment_amount) AS avg_check,
    COUNT(DISTINCT date(p2.p06)) AS active_days_count
  FROM base AS b
  LEFT JOIN pay AS p2
    ON p2.p01 = b.payment_id
  GROUP BY
    customer_id,
    customer_first_name,
    customer_last_name,
    country_name,
    month_start
),
monthly_with_prev AS (
  SELECT
    m.*,
    LAG(monthly_amount) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
    ) AS prev_month_amount
  FROM monthly AS m
),
country_month_avg AS (
  SELECT
    country_name,
    month_start,
    AVG(monthly_amount) AS country_avg_monthly_amount
  FROM monthly_with_prev
  GROUP BY
    country_name,
    month_start
),
country_rank AS (
  SELECT
    mwp.*,
    DENSE_RANK() OVER (
      PARTITION BY mwp.country_name, mwp.month_start
      ORDER BY mwp.monthly_amount DESC
    ) AS customer_country_amount_rank
  FROM monthly_with_prev AS mwp
),
staff_top AS (
  SELECT
    b.customer_id,
    b.month_start,
    b.staff_id,
    b.staff_store_id,
    SUM(b.payment_amount) AS staff_month_amount,
    ROW_NUMBER() OVER (
      PARTITION BY b.customer_id, b.month_start
      ORDER BY SUM(b.payment_amount) DESC, b.staff_id
    ) AS rn
  FROM base AS b
  GROUP BY
    b.customer_id,
    b.month_start,
    b.staff_id,
    b.staff_store_id
),
final_rows AS (
  SELECT
    cr.customer_id,
    cr.customer_first_name || ' ' || cr.customer_last_name AS customer_name,
    cr.country_name AS country,
    cr.month_start AS month,
    cr.payment_count,
    ROUND(cr.monthly_amount, 2) AS monthly_amount,
    ROUND(cr.avg_check, 2) AS avg_check,
    cr.active_days_count,
    cr.prev_month_amount,
    cam.country_avg_monthly_amount,
    cr.customer_country_amount_rank,
    c.h02 AS customer_home_store_id,
    st.staff_id AS top_staff_id,
    st.staff_store_id AS top_staff_store_id,
    s.o02 || ' ' || s.o03 AS top_staff_name,
    sto.j01 AS top_staff_store_number,
    sto.j01 AS top_store_id_reference
  FROM country_rank AS cr
  JOIN country_month_avg AS cam
    ON cam.country_name = cr.country_name
   AND cam.month_start = cr.month_start
  JOIN cus AS c
    ON c.h01 = cr.customer_id
  JOIN staff_top AS st
    ON st.customer_id = cr.customer_id
   AND st.month_start = cr.month_start
   AND st.rn = 1
  JOIN stf AS s
    ON s.o01 = st.staff_id
  JOIN sto
    ON sto.j01 = st.staff_store_id
)
SELECT
  fr.customer_id,
  fr.customer_name,
  fr.country,
  fr.month,
  fr.payment_count,
  fr.monthly_amount,
  fr.avg_check,
  fr.active_days_count,
  CASE
    WHEN fr.prev_month_amount IS NULL OR fr.prev_month_amount = 0 THEN NULL
    ELSE ROUND(fr.monthly_amount / fr.prev_month_amount, 2)
  END AS growth_vs_prev_month_ratio,
  ROUND(fr.country_avg_monthly_amount, 2) AS country_avg_monthly_amount,
  fr.customer_country_amount_rank,
  fr.customer_home_store_id AS customer_store_id,
  fr.top_staff_id AS top_staff_id,
  fr.top_staff_name AS top_staff_name,
  fr.top_store_id_reference AS staff_store_id
FROM final_rows AS fr
WHERE
  (
    fr.prev_month_amount IS NOT NULL
    AND fr.prev_month_amount > 0
    AND fr.monthly_amount >= 3.0 * fr.prev_month_amount
  )
  OR (
    fr.country_avg_monthly_amount IS NOT NULL
    AND fr.country_avg_monthly_amount > 0
    AND fr.monthly_amount > 2.0 * fr.country_avg_monthly_amount
  )
ORDER BY
  fr.month,
  fr.country,
  fr.customer_country_amount_rank,
  fr.monthly_amount DESC,
  fr.customer_id;