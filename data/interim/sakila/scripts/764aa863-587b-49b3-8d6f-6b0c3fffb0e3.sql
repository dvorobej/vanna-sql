WITH RECURSIVE
bounds AS (
  SELECT
    date(MIN(p06), 'start of month', '-3 months') AS min_month,
    date(MAX(p06), 'start of month') AS max_month
  FROM pay
),
months(month_start) AS (
  SELECT min_month
  FROM bounds
  UNION ALL
  SELECT date(month_start, '+1 month')
  FROM months, bounds
  WHERE month_start < max_month
),
customer_info AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    c.h02 AS registration_store_id,
    co.c01 AS country_id,
    co.c02 AS country,
    ci.d02 AS city
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ci.d03
),
base_pay AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    CAST(p.p05 AS REAL) AS amount,
    p.p03 AS staff_id,
    s.o07 AS staff_store_id,
    ci.registration_store_id,
    i.n02 AS film_id
  FROM pay AS p
  JOIN customer_info AS ci ON ci.customer_id = p.p02
  JOIN stf AS s ON s.o01 = p.p03
  LEFT JOIN ren AS r ON r.q01 = p.p04
  LEFT JOIN inv AS i ON i.n01 = r.q03
),
monthly_activity AS (
  SELECT
    customer_id,
    month_start,
    SUM(amount) AS payment_sum,
    COUNT(*) AS payment_count,
    MAX(amount) AS max_payment,
    COUNT(DISTINCT staff_id) AS distinct_staff_count,
    SUM(CASE WHEN staff_store_id <> registration_store_id THEN 1.0 ELSE 0.0 END) / COUNT(*) AS off_store_payment_share
  FROM base_pay
  GROUP BY customer_id, month_start
),
monthly_categories AS (
  SELECT
    bp.customer_id,
    bp.month_start,
    COUNT(DISTINCT fc.l02) AS distinct_category_count
  FROM base_pay AS bp
  JOIN flc AS fc ON fc.l01 = bp.film_id
  GROUP BY bp.customer_id, bp.month_start
),
customer_months AS (
  SELECT
    ci.customer_id,
    ci.first_name,
    ci.last_name,
    ci.country_id,
    ci.country,
    ci.city,
    m.month_start
  FROM customer_info AS ci
  CROSS JOIN months AS m
),
monthly_full AS (
  SELECT
    cm.customer_id,
    cm.first_name,
    cm.last_name,
    cm.country_id,
    cm.country,
    cm.city,
    cm.month_start,
    COALESCE(ma.payment_sum, 0.0) AS payment_sum,
    COALESCE(ma.payment_count, 0) AS payment_count,
    COALESCE(ma.max_payment, 0.0) AS max_payment,
    COALESCE(ma.distinct_staff_count, 0) AS distinct_staff_count,
    COALESCE(ma.off_store_payment_share, 0.0) AS off_store_payment_share,
    COALESCE(mc.distinct_category_count, 0) AS distinct_category_count
  FROM customer_months AS cm
  LEFT JOIN monthly_activity AS ma
    ON ma.customer_id = cm.customer_id
   AND ma.month_start = cm.month_start
  LEFT JOIN monthly_categories AS mc
    ON mc.customer_id = cm.customer_id
   AND mc.month_start = cm.month_start
),
with_history AS (
  SELECT
    mf.*,
    AVG(payment_sum) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS prev3_avg_payment_sum,
    COUNT(payment_sum) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS prev_months_count
  FROM monthly_full AS mf
),
ranked AS (
  SELECT
    wh.*,
    RANK() OVER (
      PARTITION BY country_id, month_start
      ORDER BY payment_sum DESC
    ) AS country_month_payment_rank
  FROM with_history AS wh
)
SELECT
  strftime('%Y-%m', month_start) AS payment_month,
  customer_id,
  first_name,
  last_name,
  country,
  city,
  ROUND(payment_sum, 2) AS payment_sum,
  payment_count,
  ROUND(max_payment, 2) AS max_payment,
  ROUND(off_store_payment_share, 4) AS off_store_payment_share,
  country_month_payment_rank
FROM ranked
WHERE prev_months_count = 3
  AND prev3_avg_payment_sum > 0
  AND payment_sum > 3.0 * prev3_avg_payment_sum
  AND distinct_staff_count >= 2
  AND distinct_category_count >= 3
ORDER BY
  month_start,
  country,
  country_month_payment_rank,
  customer_id;