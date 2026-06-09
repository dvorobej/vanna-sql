WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS customer_first_name,
    c.h04 AS customer_last_name,
    cnt.c02 AS country_name,
    ci.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt ON cnt.c01 = ci.d03
),
monthly_customer AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(p.p05) AS month_payment_sum,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT s.o07) AS distinct_store_count
  FROM pay AS p
  JOIN stf AS s ON s.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
monthly_customer_geo AS (
  SELECT
    mc.customer_id,
    cg.customer_first_name,
    cg.customer_last_name,
    cg.country_name,
    cg.city_name,
    mc.month_start,
    mc.month_payment_sum,
    mc.payment_count,
    mc.distinct_staff_count,
    mc.distinct_store_count
  FROM monthly_customer AS mc
  JOIN customer_geo AS cg ON cg.customer_id = mc.customer_id
),
with_prev_avg AS (
  SELECT
    mcg.*,
    AVG(mcg.month_payment_sum) OVER (
      PARTITION BY mcg.customer_id
      ORDER BY mcg.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_month_payment_sum
  FROM monthly_customer_geo AS mcg
),
candidate_months AS (
  SELECT
    w.*,
    (w.month_payment_sum - w.prev_avg_month_payment_sum) AS deviation_from_prev_avg
  FROM with_prev_avg AS w
  WHERE w.prev_avg_month_payment_sum IS NOT NULL
    AND w.payment_count >= 5
    AND w.month_payment_sum >= 2.0 * w.prev_avg_month_payment_sum
    AND (w.distinct_staff_count >= 2 OR w.distinct_store_count >= 2)
),
qualified_customers AS (
  SELECT
    customer_id
  FROM candidate_months
  WHERE strftime('%Y', month_start) = '2005'
  GROUP BY customer_id
  HAVING COUNT(*) = 11
),
final_months AS (
  SELECT
    cm.customer_id,
    cm.customer_first_name,
    cm.customer_last_name,
    cm.country_name,
    cm.city_name,
    cm.month_start,
    cm.month_payment_sum,
    cm.payment_count,
    ROUND(cm.deviation_from_prev_avg, 2) AS deviation_from_prev_avg,
    RANK() OVER (
      PARTITION BY cm.country_name, cm.month_start
      ORDER BY cm.deviation_from_prev_avg DESC
    ) AS country_deviation_rank
  FROM candidate_months AS cm
  JOIN qualified_customers AS qc ON qc.customer_id = cm.customer_id
  WHERE strftime('%Y', cm.month_start) = '2005'
)
SELECT
  strftime('%Y-%m', month_start) AS month,
  customer_id,
  customer_first_name AS first_name,
  customer_last_name AS last_name,
  country_name AS country,
  city_name AS city,
  ROUND(month_payment_sum, 2) AS month_payment_sum,
  payment_count,
  deviation_from_prev_avg,
  country_deviation_rank
FROM final_months
ORDER BY
  customer_id,
  month;