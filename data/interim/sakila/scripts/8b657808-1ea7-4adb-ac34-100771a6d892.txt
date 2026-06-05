WITH RECURSIVE
month_bounds AS (
  SELECT
    date(strftime('%Y-%m-01', MIN(p06))) AS min_month,
    date(strftime('%Y-%m-01', MAX(p06))) AS max_month
  FROM pay
),
months(month_start) AS (
  SELECT min_month
  FROM month_bounds
  WHERE min_month IS NOT NULL

  UNION ALL

  SELECT date(month_start, '+1 month')
  FROM months, month_bounds
  WHERE month_start < max_month
),
customer_country AS (
  SELECT
    cus.h01 AS customer_id,
    cus.h03 AS first_name,
    cus.h04 AS last_name,
    cus.h05 AS email,
    cnt.c01 AS country_id,
    cnt.c02 AS country_name
  FROM cus
  JOIN adr ON adr.e01 = cus.h06
  JOIN cty ON cty.d01 = adr.e05
  JOIN cnt ON cnt.c01 = cty.d03
),
payment_monthly AS (
  SELECT
    pay.p02 AS customer_id,
    date(strftime('%Y-%m-01', pay.p06)) AS month_start,
    COUNT(*) AS payment_count,
    SUM(CAST(pay.p05 AS REAL)) AS payment_amount,
    COUNT(DISTINCT pay.p03) AS distinct_staff_count,
    COUNT(DISTINCT stf.o07) AS distinct_store_count
  FROM pay
  JOIN stf ON stf.o01 = pay.p03
  GROUP BY
    pay.p02,
    date(strftime('%Y-%m-01', pay.p06))
),
monthly_customer AS (
  SELECT
    cc.customer_id,
    cc.first_name,
    cc.last_name,
    cc.email,
    cc.country_id,
    cc.country_name,
    m.month_start,
    COALESCE(pm.payment_count, 0) AS payment_count,
    COALESCE(pm.payment_amount, 0.0) AS payment_amount,
    COALESCE(pm.distinct_staff_count, 0) AS distinct_staff_count,
    COALESCE(pm.distinct_store_count, 0) AS distinct_store_count
  FROM customer_country AS cc
  CROSS JOIN months AS m
  LEFT JOIN payment_monthly AS pm
    ON pm.customer_id = cc.customer_id
   AND pm.month_start = m.month_start
),
scored AS (
  SELECT
    mc.*,
    AVG(mc.payment_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS customer_prev3_avg_amount,
    COUNT(*) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS customer_prev3_month_count
  FROM monthly_customer AS mc
),
country_month_avg AS (
  SELECT
    country_id,
    month_start,
    AVG(payment_amount) AS country_avg_amount,
    COUNT(*) AS country_customer_count
  FROM monthly_customer
  GROUP BY
    country_id,
    month_start
)
SELECT
  s.month_start AS payment_month,
  s.customer_id,
  s.first_name,
  s.last_name,
  s.email,
  s.country_name,
  s.payment_count,
  ROUND(s.payment_amount, 2) AS payment_amount,
  s.distinct_staff_count,
  s.distinct_store_count,
  ROUND(s.customer_prev3_avg_amount, 2) AS customer_prev3_avg_amount,
  ROUND(cma.country_avg_amount, 2) AS country_avg_amount,
  ROUND(s.payment_amount / NULLIF(s.customer_prev3_avg_amount, 0), 2) AS ratio_to_customer_prev3,
  ROUND(s.payment_amount / NULLIF(cma.country_avg_amount, 0), 2) AS ratio_to_country_avg,
  cma.country_customer_count
FROM scored AS s
JOIN country_month_avg AS cma
  ON cma.country_id = s.country_id
 AND cma.month_start = s.month_start
WHERE s.customer_prev3_month_count = 3
  AND s.customer_prev3_avg_amount > 0
  AND cma.country_avg_amount > 0
  AND s.payment_count >= 3
  AND s.distinct_staff_count >= 2
  AND s.payment_amount >= 2.0 * s.customer_prev3_avg_amount
  AND s.payment_amount >= 2.0 * cma.country_avg_amount
ORDER BY
  s.month_start,
  ratio_to_customer_prev3 DESC,
  ratio_to_country_avg DESC,
  s.payment_amount DESC;