WITH monthly_customer AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS month_payment_sum,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT s.o07) AS distinct_staff_store_count
  FROM pay AS p
  JOIN stf AS s
    ON s.o01 = p.p03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
customer_history AS (
  SELECT
    mc.*,
    AVG(mc.month_payment_sum) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_month_payment_sum
  FROM monthly_customer AS mc
),
qualified_months AS (
  SELECT
    *
  FROM customer_history
  WHERE prev_avg_month_payment_sum IS NOT NULL
    AND payment_count >= 5
    AND distinct_staff_count >= 2
    AND month_payment_sum >= 2.0 * prev_avg_month_payment_sum
),
customer_month_span AS (
  SELECT
    customer_id,
    MIN(month_start) AS first_month,
    MAX(month_start) AS last_month,
    COUNT(*) AS active_month_count
  FROM monthly_customer
  GROUP BY customer_id
),
monthly_all_match AS (
  SELECT
    cms.customer_id
  FROM customer_month_span AS cms
  JOIN monthly_customer AS mc
    ON mc.customer_id = cms.customer_id
  LEFT JOIN qualified_months AS qm
    ON qm.customer_id = mc.customer_id
   AND qm.month_start = mc.month_start
  GROUP BY cms.customer_id
  HAVING SUM(CASE WHEN qm.customer_id IS NOT NULL THEN 1 ELSE 0 END) = COUNT(*)
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    co.c02 AS country_name,
    ct.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ct.d03
)
SELECT
  ch.month_start AS payment_month,
  geo.customer_id,
  geo.first_name,
  geo.last_name,
  geo.country_name,
  geo.city_name,
  ROUND(ch.month_payment_sum, 2) AS month_payment_sum,
  ch.payment_count,
  ROUND(ch.prev_avg_month_payment_sum, 2) AS prev_avg_month_payment_sum,
  ROUND(ch.month_payment_sum - ch.prev_avg_month_payment_sum, 2) AS deviation_from_prev_avg,
  RANK() OVER (
    PARTITION BY geo.country_name, ch.month_start
    ORDER BY (ch.month_payment_sum - ch.prev_avg_month_payment_sum) DESC
  ) AS country_rank_by_deviation
FROM customer_history AS ch
JOIN monthly_all_match AS mam
  ON mam.customer_id = ch.customer_id
JOIN customer_geo AS geo
  ON geo.customer_id = ch.customer_id
WHERE ch.prev_avg_month_payment_sum IS NOT NULL
  AND ch.month_payment_sum >= 2.0 * ch.prev_avg_month_payment_sum
  AND ch.payment_count >= 5
  AND ch.distinct_staff_count >= 2
ORDER BY
  ch.month_start,
  geo.country_name,
  country_rank_by_deviation,
  geo.customer_id;