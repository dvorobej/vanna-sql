WITH payments_2005 AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p04 AS rental_id,
    CAST(p.p05 AS REAL) AS amount,
    date(p.p06, 'start of month') AS month_start,
    strftime('%Y-%m', p.p06) AS month_yyyy_mm
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    co.c02 AS country_name,
    ci.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
),
monthly_client AS (
  SELECT
    p.customer_id,
    p.month_start,
    COUNT(p.payment_id) AS payment_count,
    SUM(p.amount) AS monthly_sum
  FROM payments_2005 AS p
  GROUP BY p.customer_id, p.month_start
),
personal_year_avg AS (
  SELECT
    customer_id,
    AVG(monthly_sum) AS personal_avg_monthly_sum
  FROM monthly_client
  GROUP BY customer_id
),
store_month_rank AS (
  SELECT
    mc.*,
    cg.store_id,
    RANK() OVER (
      PARTITION BY cg.store_id, mc.month_start
      ORDER BY mc.monthly_sum DESC
    ) AS store_month_rank,
    COUNT(*) OVER (
      PARTITION BY cg.store_id, mc.month_start
    ) AS store_month_customers_count
  FROM monthly_client AS mc
  JOIN customer_geo AS cg
    ON cg.customer_id = mc.customer_id
),
per_month_scored AS (
  SELECT
    smr.customer_id,
    smr.month_start,
    smr.payment_count,
    smr.monthly_sum,
    pag.personal_avg_monthly_sum,
    (smr.monthly_sum - pag.personal_avg_monthly_sum) AS deviation_from_personal_avg,
    smr.store_id,
    smr.store_month_rank,
    smr.store_month_customers_count,
    smr.monthly_sum / NULLIF(pag.personal_avg_monthly_sum, 0) AS ratio_to_personal_avg
  FROM store_month_rank AS smr
  JOIN personal_year_avg AS pag
    ON pag.customer_id = smr.customer_id
),
months_ok AS (
  -- условие для каждого месяца: > 2x личного среднего
  SELECT
    pms.customer_id,
    pms.month_start
  FROM per_month_scored AS pms
  WHERE pms.personal_avg_monthly_sum IS NOT NULL
    AND pms.personal_avg_monthly_sum > 0
    AND pms.monthly_sum > 2.0 * pms.personal_avg_monthly_sum
    AND pms.store_month_rank <= CEIL(0.05 * pms.store_month_customers_count)
),
eligible_clients AS (
  -- клиент должен удовлетворить условию в каждом месяце 2005 года (12 месяцев)
  SELECT
    mo.customer_id
  FROM months_ok AS mo
  GROUP BY mo.customer_id
  HAVING COUNT(*) = 12
),
top_staff_per_month AS (
  SELECT
    p.customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.staff_id,
    ROW_NUMBER() OVER (
      PARTITION BY p.customer_id, date(p.p06, 'start of month')
      ORDER BY p.amount DESC, p.payment_id DESC
    ) AS rn
  FROM payments_2005 AS p
),
staff_choice AS (
  SELECT
    customer_id,
    month_start,
    staff_id
  FROM top_staff_per_month
  WHERE rn = 1
)
SELECT
  eg.customer_id,
  cg.store_id AS store_id,
  cg.city_name,
  cg.country_name,
  pms.month_start AS month,
  ROUND(pms.monthly_sum, 2) AS month_payment_sum,
  pms.payment_count,
  ROUND(pms.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
  pms.store_month_rank AS store_month_rank,
  st.o02 || ' ' || st.o03 AS last_staff_name
FROM eligible_clients AS eg
JOIN per_month_scored AS pms
  ON pms.customer_id = eg.customer_id
JOIN customer_geo AS cg
  ON cg.customer_id = eg.customer_id
LEFT JOIN staff_choice AS sc
  ON sc.customer_id = pms.customer_id
 AND sc.month_start = pms.month_start
LEFT JOIN stf AS st
  ON st.o01 = sc.staff_id
WHERE
  pms.month_start >= '2005-01-01'
  AND pms.month_start < '2006-01-01'
ORDER BY
  pms.customer_id,
  pms.month_start;