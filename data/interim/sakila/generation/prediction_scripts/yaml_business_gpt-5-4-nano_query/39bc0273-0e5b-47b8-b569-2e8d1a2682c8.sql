WITH payments_monthly AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    c.h02 AS registration_store_id,
    cn.c02 AS country_name,
    p.p03 AS staff_id,
    p.p04 AS rental_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS monthly_sum,
    AVG(CAST(p.p05 AS REAL)) AS avg_check,
    COUNT(DISTINCT date(p.p06)) AS active_days,
    SUM(CASE WHEN p.p05 IS NOT NULL THEN CAST(p.p05 AS REAL) ELSE 0 END) AS monthly_sum_for_rank
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
    c.h01, c.h03, c.h04, c.h02, cn.c02,
    p.p03,
    date(p.p06, 'start of month')
),
customer_month AS (
  SELECT
    customer_id,
    first_name,
    last_name,
    registration_store_id,
    country_name,
    month_start,
    SUM(payment_count) AS payment_count,
    SUM(monthly_sum) AS monthly_sum,
    AVG(avg_check) AS avg_check,
    SUM(active_days) AS active_days
  FROM payments_monthly
  GROUP BY
    customer_id, first_name, last_name, registration_store_id, country_name, month_start
),
customer_prev AS (
  SELECT
    cm.*,
    LAG(cm.monthly_sum) OVER (
      PARTITION BY cm.customer_id
      ORDER BY cm.month_start
    ) AS prev_monthly_sum
  FROM customer_month AS cm
),
country_avg_month AS (
  SELECT
    country_name,
    month_start,
    AVG(monthly_sum) AS country_avg_monthly_sum
  FROM customer_month
  GROUP BY country_name, month_start
),
staff_max_payment AS (
  SELECT
    c.h01 AS customer_id,
    cn.c02 AS country_name,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id,
    SUM(CAST(p.p05 AS REAL)) AS staff_monthly_sum,
    ROW_NUMBER() OVER (
      PARTITION BY c.h01, date(p.p06, 'start of month')
      ORDER BY SUM(CAST(p.p05 AS REAL)) DESC, p.p03
    ) AS staff_rn
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
    c.h01, cn.c02, date(p.p06, 'start of month'), p.p03
)
SELECT
  cpm.customer_id,
  cpm.first_name,
  cpm.last_name,
  cpm.country_name AS country,
  cpm.registration_store_id AS store_id,
  cpm.month_start AS month,
  cpm.payment_count,
  ROUND(cpm.monthly_sum, 2) AS monthly_sum,
  ROUND(cpm.avg_check, 2) AS avg_check,
  cpm.active_days AS active_days,
  cpm.prev_monthly_sum,
  ROUND(cpm.monthly_sum / NULLIF(cpm.prev_monthly_sum, 0), 4) AS monthly_sum_vs_prev_ratio,
  ROUND(cam.country_avg_monthly_sum, 2) AS country_avg_monthly_sum,
  ROUND(cpm.monthly_sum / NULLIF(cam.country_avg_monthly_sum, 0), 4) AS monthly_sum_vs_country_avg_ratio,
  RANK() OVER (
    PARTITION BY cpm.country_name, cpm.month_start
    ORDER BY cpm.monthly_sum DESC
  ) AS customer_country_amount_rank,
  smp.staff_id AS top_staff_id
FROM customer_prev AS cpm
JOIN country_avg_month AS cam
  ON cam.country_name = cpm.country_name
 AND cam.month_start = cpm.month_start
JOIN staff_max_payment AS smp
  ON smp.customer_id = cpm.customer_id
 AND smp.country_name = cpm.country_name
 AND smp.month_start = cpm.month_start
 AND smp.staff_rn = 1
WHERE
  cpm.prev_monthly_sum IS NOT NULL
  AND (
    cpm.monthly_sum >= 3.0 * cpm.prev_monthly_sum
    OR cpm.monthly_sum > 2.0 * cam.country_avg_monthly_sum
  )
ORDER BY
  cpm.month_start,
  cpm.country_name,
  customer_country_amount_rank,
  cpm.customer_id;