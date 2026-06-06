WITH monthly_customer AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    ct.d01 AS city_id,
    ct.d02 AS city,
    cn.c01 AS country_id,
    cn.c02 AS country,
    strftime('%Y-%m', p.p06) AS payment_month,
    COUNT(p.p01) AS payment_count,
    SUM(p.p05) AS total_amount,
    AVG(p.p05) AS average_check,
    COUNT(DISTINCT p.p03) AS staff_count,
    MAX(p.p05) AS max_payment
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
    c.h01,
    c.h03,
    c.h04,
    ct.d01,
    ct.d02,
    cn.c01,
    cn.c02,
    strftime('%Y-%m', p.p06)
),
monthly_with_prev AS (
  SELECT
    mc.*,
    LAG(mc.total_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.payment_month
    ) AS previous_month_amount
  FROM monthly_customer AS mc
),
city_country_stats AS (
  SELECT
    payment_month,
    city_id,
    country_id,
    AVG(total_amount) AS city_avg_total_amount,
    AVG(payment_count * 1.0) AS city_avg_payment_count,
    AVG(average_check) AS city_avg_check,
    AVG(total_amount) OVER (
      PARTITION BY country_id, payment_month
    ) AS country_avg_total_amount,
    AVG(payment_count * 1.0) OVER (
      PARTITION BY country_id, payment_month
    ) AS country_avg_payment_count,
    AVG(average_check) OVER (
      PARTITION BY country_id, payment_month
    ) AS country_avg_check
  FROM monthly_with_prev
  GROUP BY
    payment_month,
    city_id,
    country_id
),
ranked AS (
  SELECT
    mwp.*,
    ccs.city_avg_total_amount,
    ccs.city_avg_payment_count,
    ccs.city_avg_check,
    ccs.country_avg_total_amount,
    ccs.country_avg_payment_count,
    ccs.country_avg_check,
    RANK() OVER (
      PARTITION BY mwp.country_id, mwp.payment_month
      ORDER BY mwp.total_amount DESC
    ) AS country_amount_rank,
    COUNT(*) OVER (
      PARTITION BY mwp.country_id, mwp.payment_month
    ) AS country_customer_count
  FROM monthly_with_prev AS mwp
  JOIN city_country_stats AS ccs
    ON ccs.payment_month = mwp.payment_month
   AND ccs.city_id = mwp.city_id
   AND ccs.country_id = mwp.country_id
  WHERE mwp.payment_month >= '2005-01'
    AND mwp.payment_month <= '2005-12'
)
SELECT
  customer_id,
  first_name,
  last_name,
  city,
  country,
  payment_month,
  payment_count,
  ROUND(total_amount, 2) AS total_amount,
  ROUND(average_check, 2) AS average_check,
  ROUND(city_avg_total_amount, 2) AS city_avg_total_amount,
  ROUND(city_avg_payment_count, 2) AS city_avg_payment_count,
  ROUND(city_avg_check, 2) AS city_avg_check,
  ROUND(country_avg_total_amount, 2) AS country_avg_total_amount,
  ROUND(country_avg_payment_count, 2) AS country_avg_payment_count,
  ROUND(country_avg_check, 2) AS country_avg_check,
  ROUND(previous_month_amount, 2) AS previous_month_amount,
  CASE
    WHEN previous_month_amount IS NULL OR previous_month_amount = 0 THEN NULL
    ELSE ROUND((total_amount - previous_month_amount) * 100.0 / previous_month_amount, 2)
  END AS percent_growth_to_previous_month,
  staff_count,
  ROUND(max_payment, 2) AS max_payment,
  country_amount_rank
FROM ranked
WHERE total_amount >= city_avg_total_amount * 3
   OR country_amount_rank <= CAST((country_customer_count + 19) / 20 AS INTEGER)
ORDER BY
  payment_month,
  country,
  country_amount_rank,
  total_amount DESC,
  customer_id;