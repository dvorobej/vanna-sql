WITH monthly_customer AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(p.p01) AS payment_count,
    SUM(p.p05) AS payment_sum,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT s.o07) AS distinct_store_count
  FROM pay AS p
  JOIN stf AS s
    ON s.o01 = p.p03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
customer_base AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    co.c02 AS country,
    ct.d02 AS city
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ct.d03
),
monthly_with_prev AS (
  SELECT
    mc.*,
    AVG(mc.payment_sum) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_payment_sum
  FROM monthly_customer AS mc
),
qualifying_months AS (
  SELECT
    mwp.*,
    cb.first_name,
    cb.last_name,
    cb.country,
    cb.city,
    (mwp.payment_sum - mwp.prev_avg_payment_sum) AS deviation_from_prev_avg,
    ROW_NUMBER() OVER (
      PARTITION BY mwp.month_start, cb.country
      ORDER BY (mwp.payment_sum - mwp.prev_avg_payment_sum) DESC, mwp.customer_id
    ) AS country_month_rank_by_deviation
  FROM monthly_with_prev AS mwp
  JOIN customer_base AS cb
    ON cb.customer_id = mwp.customer_id
  WHERE mwp.prev_avg_payment_sum IS NOT NULL
    AND mwp.payment_count >= 5
    AND (mwp.distinct_staff_count >= 2 OR mwp.distinct_store_count >= 2)
    AND mwp.payment_sum >= 2.0 * mwp.prev_avg_payment_sum
),
flagged_clients AS (
  SELECT
    customer_id
  FROM qualifying_months
  GROUP BY customer_id
  HAVING COUNT(*) = 12
)
SELECT
  qm.month_start AS payment_month,
  qm.customer_id,
  qm.first_name,
  qm.last_name,
  qm.country,
  qm.city,
  ROUND(qm.payment_sum, 2) AS payment_sum,
  qm.payment_count,
  ROUND(qm.prev_avg_payment_sum, 2) AS prev_avg_payment_sum,
  ROUND(qm.deviation_from_prev_avg, 2) AS deviation_from_prev_avg,
  qm.country_month_rank_by_deviation AS country_month_rank_by_deviation
FROM qualifying_months AS qm
JOIN flagged_clients AS fc
  ON fc.customer_id = qm.customer_id
ORDER BY
  qm.month_start,
  qm.country,
  qm.country_month_rank_by_deviation,
  qm.customer_id;