SELECT date('2005-01-01','start of month') AS month_start
  UNION ALL
  SELECT date(month_start,'+1 month')
  FROM month_list
  WHERE month_start < date('2005-12-01','start of month')
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS customer_first_name,
    c.h04 AS customer_last_name,
    co.c02 AS country_name,
    ct.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ct ON ct.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ct.d03
),
payments_2005 AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p03 AS staff_id,
    s.o07 AS store_id
  FROM pay AS p
  JOIN cus AS c ON c.h01 = p.p02
  JOIN ren AS r ON r.q01 = p.p04
  JOIN stf AS s ON s.o01 = p.p03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
),
customer_months AS (
  SELECT
    cg.customer_id,
    cg.customer_first_name,
    cg.customer_last_name,
    cg.country_name,
    cg.city_name,
    ml.month_start
  FROM customer_geo AS cg
  CROSS JOIN month_list AS ml
),
monthly_stats AS (
  SELECT
    cm.customer_id,
    cm.customer_first_name,
    cm.customer_last_name,
    cm.country_name,
    cm.city_name,
    cm.month_start,
    COALESCE(SUM(p.payment_amount), 0.0) AS month_payment_sum,
    COALESCE(COUNT(p.payment_amount), 0) AS month_payment_count,
    COALESCE(COUNT(DISTINCT p.staff_id), 0) AS distinct_staff_count,
    COALESCE(COUNT(DISTINCT p.store_id), 0) AS distinct_store_count
  FROM customer_months AS cm
  LEFT JOIN payments_2005 AS p
    ON p.customer_id = cm.customer_id
   AND p.month_start = cm.month_start
  GROUP BY
    cm.customer_id,
    cm.customer_first_name,
    cm.customer_last_name,
    cm.country_name,
    cm.city_name,
    cm.month_start
),
with_prev_avg AS (
  SELECT
    ms.*,
    AVG(month_payment_sum) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_monthly_sum
  FROM monthly_stats AS ms
),
qualifying_months AS (
  SELECT *
  FROM with_prev_avg
  WHERE prev_avg_monthly_sum IS NOT NULL
    AND month_payment_count >= 5
    AND month_payment_sum >= 2.0 * prev_avg_monthly_sum
    AND (distinct_staff_count >= 2 OR distinct_store_count >= 2)
),
qualified_clients AS (
  SELECT
    customer_id
  FROM qualifying_months
  GROUP BY customer_id
  HAVING COUNT(DISTINCT month_start) = 11
)
SELECT
  qm.customer_id,
  qm.customer_first_name,
  qm.customer_last_name,
  qm.country_name,
  qm.city_name,
  strftime('%Y-%m', qm.month_start) AS month,
  ROUND(qm.month_payment_sum, 2) AS month_payment_sum,
  qm.month_payment_count,
  ROUND(qm.month_payment_sum - qm.prev_avg_monthly_sum, 2) AS deviation_from_prev_avg,
  RANK() OVER (
    PARTITION BY qm.country_name, qm.month_start
    ORDER BY (qm.month_payment_sum - qm.prev_avg_monthly_sum) DESC
  ) AS country_month_deviation_rank
FROM qualifying_months AS qm
JOIN qualified_clients AS qc
  ON qc.customer_id = qm.customer_id
ORDER BY
  qm.month_start,
  qm.country_name,
  country_month_deviation_rank,
  qm.customer_id;