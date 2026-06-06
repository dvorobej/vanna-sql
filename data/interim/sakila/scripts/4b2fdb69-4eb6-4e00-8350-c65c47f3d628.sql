WITH RECURSIVE
payment_bounds AS (
  SELECT
    date(MIN(p06), 'start of month') AS min_month,
    date(MAX(p06), 'start of month') AS max_month
  FROM pay
  WHERE p04 IS NOT NULL
),
months(month_start) AS (
  SELECT min_month
  FROM payment_bounds
  WHERE min_month IS NOT NULL

  UNION ALL

  SELECT date(month_start, '+1 month')
  FROM months
  CROSS JOIN payment_bounds
  WHERE month_start < max_month
),
customer_geo AS (
  SELECT
    cus.h01 AS customer_id,
    cus.h03 AS first_name,
    cus.h04 AS last_name,
    cty.d01 AS city_id,
    cty.d02 AS city_name,
    cnt.c01 AS country_id,
    cnt.c02 AS country_name
  FROM cus
  JOIN adr ON adr.e01 = cus.h06
  JOIN cty ON cty.d01 = adr.e05
  JOIN cnt ON cnt.c01 = cty.d03
),
customer_months AS (
  SELECT
    customer_geo.customer_id,
    customer_geo.first_name,
    customer_geo.last_name,
    customer_geo.city_id,
    customer_geo.city_name,
    customer_geo.country_id,
    customer_geo.country_name,
    months.month_start
  FROM customer_geo
  CROSS JOIN months
),
monthly_payments AS (
  SELECT
    pay.p02 AS customer_id,
    date(pay.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(pay.p05) AS month_total
  FROM pay
  WHERE pay.p04 IS NOT NULL
  GROUP BY
    pay.p02,
    date(pay.p06, 'start of month')
),
monthly_base AS (
  SELECT
    customer_months.customer_id,
    customer_months.first_name,
    customer_months.last_name,
    customer_months.city_id,
    customer_months.city_name,
    customer_months.country_id,
    customer_months.country_name,
    customer_months.month_start,
    COALESCE(monthly_payments.payment_count, 0) AS payment_count,
    COALESCE(monthly_payments.month_total, 0.0) AS month_total,
    CASE
      WHEN COALESCE(monthly_payments.payment_count, 0) > 0
      THEN monthly_payments.month_total * 1.0 / monthly_payments.payment_count
      ELSE 0.0
    END AS avg_check
  FROM customer_months
  LEFT JOIN monthly_payments
    ON monthly_payments.customer_id = customer_months.customer_id
   AND monthly_payments.month_start = customer_months.month_start
),
monthly_with_prev AS (
  SELECT
    monthly_base.*,
    AVG(month_total) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS prev_3m_avg,
    COUNT(*) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS prev_3m_count
  FROM monthly_base
),
country_month_ranked AS (
  SELECT
    monthly_with_prev.*,
    RANK() OVER (
      PARTITION BY country_id, month_start
      ORDER BY month_total DESC
    ) AS country_month_payment_rank,
    COUNT(*) OVER (
      PARTITION BY country_id, month_start
    ) AS country_month_customer_count
  FROM monthly_with_prev
),
qualified AS (
  SELECT *
  FROM country_month_ranked
  WHERE payment_count > 0
    AND prev_3m_count = 3
    AND prev_3m_avg > 0
    AND month_total >= prev_3m_avg * 3
    AND country_month_payment_rank <= (country_month_customer_count + 19) / 20
),
monthly_staff_counts AS (
  SELECT
    pay.p02 AS customer_id,
    date(pay.p06, 'start of month') AS month_start,
    pay.p03 AS staff_id,
    COUNT(*) AS staff_payment_count
  FROM pay
  WHERE pay.p04 IS NOT NULL
  GROUP BY
    pay.p02,
    date(pay.p06, 'start of month'),
    pay.p03
),
monthly_staff_share AS (
  SELECT
    customer_id,
    month_start,
    MAX(staff_payment_count) * 1.0 / SUM(staff_payment_count) AS same_staff_payment_share
  FROM monthly_staff_counts
  GROUP BY
    customer_id,
    month_start
),
monthly_store_category AS (
  SELECT
    pay.p02 AS customer_id,
    date(pay.p06, 'start of month') AS month_start,
    COUNT(DISTINCT inv.n03) AS distinct_store_count,
    COUNT(DISTINCT flc.l02) AS distinct_category_count
  FROM pay
  JOIN ren ON ren.q01 = pay.p04
  JOIN inv ON inv.n01 = ren.q03
  LEFT JOIN flc ON flc.l01 = inv.n02
  WHERE pay.p04 IS NOT NULL
  GROUP BY
    pay.p02,
    date(pay.p06, 'start of month')
)
SELECT
  qualified.country_name AS country,
  qualified.city_name AS city,
  qualified.customer_id,
  qualified.first_name,
  qualified.last_name,
  qualified.month_start AS payment_month,
  qualified.payment_count,
  ROUND(qualified.month_total, 2) AS total_amount,
  ROUND(qualified.avg_check, 2) AS average_check,
  ROUND(COALESCE(monthly_staff_share.same_staff_payment_share, 0.0), 4) AS same_staff_payment_share,
  COALESCE(monthly_store_category.distinct_store_count, 0) AS distinct_store_count,
  COALESCE(monthly_store_category.distinct_category_count, 0) AS distinct_category_count,
  DENSE_RANK() OVER (
    PARTITION BY qualified.country_id
    ORDER BY qualified.month_total DESC
  ) AS country_risk_rank
FROM qualified
LEFT JOIN monthly_staff_share
  ON monthly_staff_share.customer_id = qualified.customer_id
 AND monthly_staff_share.month_start = qualified.month_start
LEFT JOIN monthly_store_category
  ON monthly_store_category.customer_id = qualified.customer_id
 AND monthly_store_category.month_start = qualified.month_start
ORDER BY
  qualified.country_name,
  country_risk_rank,
  qualified.month_total DESC,
  qualified.customer_id;