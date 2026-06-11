WITH month_payments AS (
  SELECT
    p.p02 AS customer_id,
    c.h03 AS customer_first_name,
    c.h04 AS customer_last_name,
    c.h02 AS customer_store_id,
    cn.c01 AS country_id,
    cn.c02 AS country_name,
    strftime('%Y-%m', p.p06) AS month_start,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS monthly_amount,
    AVG(p.p05) AS avg_check,
    COUNT(DISTINCT DATE(p.p06)) AS distinct_payment_days,
    SUM(p.p05) OVER (PARTITION BY p.p02, strftime('%Y-%m', p.p06)) AS monthly_amount_for_rank
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS cn
    ON cn.c01 = ct.d03
  GROUP BY
    p.p02,
    c.h03,
    c.h04,
    c.h02,
    cn.c01,
    cn.c02,
    strftime('%Y-%m', p.p06)
),
with_comparisons AS (
  SELECT
    mp.*,
    LAG(mp.monthly_amount) OVER (
      PARTITION BY mp.customer_id
      ORDER BY mp.month_start
    ) AS prev_monthly_amount,
    AVG(mp.monthly_amount) OVER (
      PARTITION BY mp.country_id, mp.month_start
    ) AS country_month_avg_monthly_amount
  FROM month_payments AS mp
),
top_staff_month AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS month_start,
    p.p03 AS staff_id,
    SUM(p.p05) AS staff_month_amount,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, strftime('%Y-%m', p.p06)
      ORDER BY SUM(p.p05) DESC, p.p03
    ) AS rn
  FROM pay AS p
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06),
    p.p03
),
staff_details AS (
  SELECT
    ts.customer_id,
    ts.month_start,
    ts.staff_id,
    s.o02 || ' ' || s.o03 AS top_staff_name,
    ts.staff_month_amount AS top_staff_month_amount
  FROM top_staff_month AS ts
  JOIN stf AS s
    ON s.o01 = ts.staff_id
  WHERE ts.rn = 1
)
SELECT
  wc.customer_id,
  wc.customer_first_name,
  wc.customer_last_name,
  wc.country_name AS country,
  wc.customer_store_id AS store_id,
  wc.month_start AS month,
  wc.payment_count,
  ROUND(wc.monthly_amount, 2) AS monthly_amount,
  ROUND(wc.avg_check, 2) AS avg_check,
  wc.distinct_payment_days,
  ROUND(wc.prev_monthly_amount, 2) AS prev_monthly_amount,
  ROUND(wc.country_month_avg_monthly_amount, 2) AS country_month_avg_monthly_amount,
  RANK() OVER (
    PARTITION BY wc.country_id, wc.month_start
    ORDER BY wc.monthly_amount DESC
  ) AS customer_country_month_rank,
  sd.top_staff_id AS top_staff_id,
  sd.top_staff_name AS top_staff_name,
  ROUND(sd.top_staff_month_amount, 2) AS top_staff_month_amount
FROM with_comparisons AS wc
LEFT JOIN staff_details AS sd
  ON sd.customer_id = wc.customer_id
 AND sd.month_start = wc.month_start
WHERE
  (
    wc.prev_monthly_amount IS NOT NULL
    AND wc.prev_monthly_amount > 0
    AND wc.monthly_amount >= 3.0 * wc.prev_monthly_amount
  )
  OR (
    wc.country_month_avg_monthly_amount IS NOT NULL
    AND wc.country_month_avg_monthly_amount > 0
    AND wc.monthly_amount >= 2.0 * wc.country_month_avg_monthly_amount
  )
ORDER BY
  wc.month_start,
  wc.country_name,
  customer_country_month_rank,
  wc.customer_id;