WITH monthly_customer AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    c.h07 AS active_status,
    c.h02 AS store_id,
    city.d01 AS city_id,
    city.d02 AS city_name,
    country.c01 AS country_id,
    country.c02 AS country_name,
    strftime('%Y-%m', p.p06) AS payment_month,
    SUM(p.p05) AS monthly_amount,
    COUNT(p.p01) AS payment_count,
    COUNT(DISTINCT p.p03) AS staff_count,
    MAX(p.p05) AS max_payment
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS city
    ON city.d01 = a.e05
  JOIN cnt AS country
    ON country.c01 = city.d03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    c.h01,
    c.h03,
    c.h04,
    c.h07,
    c.h02,
    city.d01,
    city.d02,
    country.c01,
    country.c02,
    strftime('%Y-%m', p.p06)
),
monthly_with_stats AS (
  SELECT
    mc.*,
    AVG(mc.monthly_amount) OVER (
      PARTITION BY mc.city_id, mc.payment_month
    ) AS city_avg_monthly_amount,
    AVG(mc.monthly_amount) OVER (
      PARTITION BY mc.country_id, mc.payment_month
    ) AS country_avg_monthly_amount,
    LAG(mc.monthly_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.payment_month
    ) AS previous_monthly_amount
  FROM monthly_customer AS mc
)
SELECT
  customer_id,
  first_name,
  last_name,
  country_name,
  city_name,
  store_id,
  payment_month,
  payment_count,
  ROUND(monthly_amount, 2) AS monthly_amount,
  ROUND(city_avg_monthly_amount, 2) AS city_avg_monthly_amount,
  ROUND(country_avg_monthly_amount, 2) AS country_avg_monthly_amount,
  ROUND(previous_monthly_amount, 2) AS previous_monthly_amount,
  ROUND(monthly_amount - COALESCE(previous_monthly_amount, 0), 2) AS growth_to_previous_month,
  staff_count,
  ROUND(max_payment, 2) AS max_payment,
  CASE
    WHEN monthly_amount > city_avg_monthly_amount
     AND monthly_amount > country_avg_monthly_amount
    THEN 1
    ELSE 0
  END AS suspicious_activity
FROM monthly_with_stats
WHERE active_status IN ('1', 'Y', 'y')
  AND monthly_amount > city_avg_monthly_amount
  AND monthly_amount > country_avg_monthly_amount
ORDER BY
  payment_month,
  country_name,
  city_name,
  monthly_amount DESC,
  customer_id;