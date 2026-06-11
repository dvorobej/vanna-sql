WITH base AS (
  SELECT
    p.p02 AS customer_id,
    c.h02 AS registration_store_id,
    date(p.p06, 'start of month') AS month_start,
    CAST(p.p05 AS REAL) AS amount,
    p.p05 AS amount_raw,
    p.p01 AS payment_id,
    p.p03 AS staff_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cnt.c01 AS country_id,
    cnt.c02 AS country_name,
    ci.d02 AS city_name
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS cnt
    ON cnt.c01 = ci.d03
),
monthly_customer AS (
  SELECT
    customer_id,
    registration_store_id,
    month_start,
    first_name,
    last_name,
    country_id,
    country_name,
    city_name,
    COUNT(*) AS payment_count,
    SUM(amount) AS monthly_amount_sum,
    AVG(amount) AS avg_check,
    COUNT(DISTINCT date(p06)) AS payment_days
  FROM base
  GROUP BY
    customer_id,
    registration_store_id,
    month_start,
    first_name,
    last_name,
    country_id,
    country_name,
    city_name
),
monthly_with_prev AS (
  SELECT
    mc.*,
    LAG(monthly_amount_sum, 1) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
    ) AS prev_month_amount_sum
  FROM monthly_customer AS mc
),
country_month_avg AS (
  SELECT
    country_id,
    month_start,
    AVG(monthly_amount_sum) AS country_avg_monthly_amount
  FROM monthly_customer
  GROUP BY country_id, month_start
),
staff_month_top AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id,
    SUM(CAST(p.p05 AS REAL)) AS staff_month_amount_sum,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, date(p.p06, 'start of month')
      ORDER BY SUM(CAST(p.p05 AS REAL)) DESC, p.p03
    ) AS rn
  FROM pay AS p
  GROUP BY
    p.p02,
    date(p.p06, 'start of month'),
    p.p03
),
filtered AS (
  SELECT
    mwp.*,
    (mwp.monthly_amount_sum / NULLIF(mwp.prev_month_amount_sum, 0)) AS ratio_to_prev_month,
    (mwp.monthly_amount_sum / NULLIF(cma.country_avg_monthly_amount, 0)) AS ratio_to_country_avg
  FROM monthly_with_prev AS mwp
  JOIN country_month_avg AS cma
    ON cma.country_id = mwp.country_id
   AND cma.month_start = mwp.month_start
)
SELECT
  f.customer_id AS h01,
  f.first_name,
  f.last_name,
  f.country_name AS c02,
  f.city_name AS d02,
  f.registration_store_id AS j01,
  f.month_start AS month,
  f.payment_count,
  ROUND(f.monthly_amount_sum, 2) AS monthly_amount_sum,
  ROUND(f.avg_check, 2) AS avg_check,
  f.payment_days AS distinct_payment_dates,
  ROUND(f.ratio_to_prev_month, 3) AS ratio_to_prev_month,
  ROUND(f.ratio_to_country_avg, 3) AS ratio_to_country_avg,
  RANK() OVER (
    PARTITION BY f.country_id, f.month_start
    ORDER BY f.monthly_amount_sum DESC
  ) AS rank_within_country,
  top_staff.staff_id AS top_staff_o01
FROM filtered AS f
LEFT JOIN (
  SELECT customer_id, month_start, staff_id
  FROM staff_month_top
  WHERE rn = 1
) AS top_staff
  ON top_staff.customer_id = f.customer_id
 AND top_staff.month_start = f.month_start
WHERE
  f.prev_month_amount_sum IS NOT NULL
  AND (
    f.monthly_amount_sum >= 3.0 * f.prev_month_amount_sum
    OR f.monthly_amount_sum >= 2.0 * (
      SELECT country_avg_monthly_amount
      FROM country_month_avg cma
      WHERE cma.country_id = f.country_id
        AND cma.month_start = f.month_start
    )
  )
ORDER BY
  f.month_start,
  f.country_name,
  monthly_amount_sum DESC,
  f.customer_id;