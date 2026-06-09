WITH
customer_base AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    c.h02 AS home_store_id,
    cnt.c01 AS country_id,
    cnt.c02 AS country_name,
    cty.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS cty ON cty.d01 = a.e05
  JOIN cnt ON cnt.c01 = cty.d03
),
monthly_payments AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(p.p05) AS month_amount_sum,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay AS p
  JOIN stf AS s ON s.o01 = p.p03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
monthly_with_avgs AS (
  SELECT
    mp.*,
    AVG(mp.month_amount_sum) OVER (
      PARTITION BY mp.customer_id
      ORDER BY mp.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_month_amount
  FROM monthly_payments AS mp
),
qualified_months AS (
  SELECT
    mwa.*
  FROM monthly_with_avgs AS mwa
  WHERE
    mwa.prev_avg_month_amount > 0
    AND mwa.month_amount_sum >= 2.0 * mwa.prev_avg_month_amount
    AND mwa.payment_count >= 5
    AND (mwa.staff_count >= 2 OR mwa.store_count >= 2)
),
months_2005_per_customer AS (
  SELECT
    customer_id,
    COUNT(DISTINCT month_start) AS months_2005_count
  FROM monthly_payments
  GROUP BY customer_id
),
qualified_months_per_customer AS (
  SELECT
    customer_id,
    COUNT(DISTINCT month_start) AS qualified_months_count
  FROM qualified_months
  GROUP BY customer_id
),
customers_all_months_ok AS (
  SELECT
    m.customer_id
  FROM months_2005_per_customer AS m
  JOIN qualified_months_per_customer AS q
    ON q.customer_id = m.customer_id
  WHERE m.months_2005_count = 12
    AND q.qualified_months_count = 12
),
ranked AS (
  SELECT
    k.customer_id,
    cb.country_id,
    cb.country_name,
    cb.city_name,
    mwa.month_start,
    mwa.month_amount_sum,
    mwa.payment_count,
    (mwa.month_amount_sum - mwa.prev_avg_month_amount) AS deviation_from_avg_amount,
    RANK() OVER (
      PARTITION BY cb.country_id, mwa.month_start
      ORDER BY mwa.month_amount_sum DESC
    ) AS country_month_rank
  FROM customers_all_months_ok AS k
  JOIN qualified_months AS mwa
    ON mwa.customer_id = k.customer_id
  JOIN customer_base AS cb
    ON cb.customer_id = k.customer_id
)
SELECT
  strftime('%Y-%m', r.month_start) AS payment_month,
  r.country_name AS country,
  r.city_name AS city,
  ROUND(r.month_amount_sum, 2) AS month_amount_sum,
  r.payment_count,
  ROUND(r.deviation_from_avg_amount, 2) AS deviation_from_avg_amount,
  r.country_month_rank
FROM ranked AS r
ORDER BY
  r.month_start,
  r.country_name,
  r.country_month_rank;