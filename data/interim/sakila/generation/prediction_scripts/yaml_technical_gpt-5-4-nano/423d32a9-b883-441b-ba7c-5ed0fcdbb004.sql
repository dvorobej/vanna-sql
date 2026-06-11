WITH
payment_base AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p01 AS payment_id,
    p.p05 AS payment_amount,
    p.p03 AS staff_id,
    c.h02 AS customer_store_id,
    co.c01 AS customer_country_id,
    co.c02 AS customer_country,
    ci.d02 AS customer_city,
    s.o07 AS staff_store_id
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN stf AS s
    ON s.o01 = p.p03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
),
monthly_customer AS (
  SELECT
    customer_id,
    month_start,
    MAX(customer_country_id) AS customer_country_id,
    MAX(customer_country) AS customer_country,
    MAX(customer_city) AS customer_city,

    COUNT(*) AS payment_count,
    SUM(payment_amount) AS monthly_amount,
    COUNT(DISTINCT staff_id) AS distinct_staff_count,

    COUNT(DISTINCT staff_store_id) AS distinct_staff_store_count,
    COUNT(DISTINCT customer_store_id) AS distinct_customer_store_count,

    MAX(CASE WHEN staff_store_id <> customer_store_id THEN 1 ELSE 0 END) AS has_other_store_staff
  FROM payment_base
  GROUP BY customer_id, month_start
),
with_history AS (
  SELECT
    mc.*,
    AVG(mc.monthly_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS avg_prev_monthly_amount,
    COUNT(*) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_months_count
  FROM monthly_customer mc
),
qualifying AS (
  SELECT
    wh.*
  FROM with_history wh
  WHERE wh.prev_months_count > 0
    AND wh.payment_count >= 5
    AND wh.monthly_amount >= 2.0 * wh.avg_prev_monthly_amount
    AND (
      wh.distinct_staff_count >= 2
      OR wh.has_other_store_staff = 1
      OR wh.distinct_staff_store_count >= 2
    )
),
ranked AS (
  SELECT
    q.*,
    (q.monthly_amount - q.avg_prev_monthly_amount) AS deviation_from_prev_avg,
    RANK() OVER (
      PARTITION BY q.customer_country_id
      ORDER BY (q.monthly_amount - q.avg_prev_monthly_amount) DESC
    ) AS country_rank
  FROM qualifying q
)
SELECT
  customer_id AS h01,
  customer_country,
  customer_city,
  month_start AS month,
  payment_count AS monthly_payment_count,
  ROUND(monthly_amount, 2) AS monthly_amount,
  ROUND(avg_prev_monthly_amount, 2) AS avg_prev_monthly_amount,
  ROUND(deviation_from_prev_avg, 2) AS deviation_from_prev_avg,
  distinct_staff_count AS distinct_staff_count,
  distinct_staff_store_count AS distinct_staff_store_count,
  country_rank
FROM ranked
ORDER BY
  customer_country,
  country_rank,
  month_start,
  customer_id;