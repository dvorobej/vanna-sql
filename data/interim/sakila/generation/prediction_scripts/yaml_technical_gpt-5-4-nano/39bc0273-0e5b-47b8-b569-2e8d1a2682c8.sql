WITH payments_base AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p01 AS payment_id,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p03 AS staff_id
  FROM pay AS p
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    ci.c01 AS country_id,
    ci.c02 AS country_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ct ON ct.d01 = a.e05
  JOIN cnt AS ci ON ci.c01 = ct.d03
),
monthly_customer AS (
  SELECT
    pb.customer_id,
    cg.store_id,
    cg.country_id,
    cg.country_name,
    pb.month_start,
    COUNT(*) AS payment_count,
    SUM(pb.payment_amount) AS month_payment_sum,
    AVG(pb.payment_amount) AS avg_check,
    COUNT(DISTINCT pb.payment_id) AS distinct_payment_dates,
    COUNT(DISTINCT pb.payment_id) AS distinct_dates_count_dummy
  FROM payments_base pb
  JOIN customer_geo cg ON cg.customer_id = pb.customer_id
  GROUP BY
    pb.customer_id, cg.store_id, cg.country_id, cg.country_name, pb.month_start
),
monthly_customer_fixed AS (
  SELECT
    mc.*,
    COUNT(DISTINCT pb2.payment_id) AS distinct_payment_dates_count
  FROM monthly_customer mc
  JOIN payments_base pb2
    ON pb2.customer_id = mc.customer_id
   AND pb2.month_start = mc.month_start
  GROUP BY
    mc.customer_id, mc.store_id, mc.country_id, mc.country_name, mc.month_start,
    mc.payment_count, mc.month_payment_sum, mc.avg_check
),
monthly_with_prev AS (
  SELECT
    mc.*,
    LAG(mc.month_payment_sum) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
    ) AS prev_month_payment_sum
  FROM monthly_customer_fixed mc
),
country_month_stats AS (
  SELECT
    country_id,
    month_start,
    AVG(month_payment_sum) AS country_avg_month_payment_sum
  FROM monthly_with_prev
  GROUP BY country_id, month_start
),
qualified_months AS (
  SELECT
    mwp.*,
    cms.country_avg_month_payment_sum,
    CASE
      WHEN mwp.prev_month_payment_sum IS NOT NULL AND mwp.prev_month_payment_sum > 0
      THEN mwp.month_payment_sum / mwp.prev_month_payment_sum
      ELSE NULL
    END AS growth_multiplier_vs_prev_month
  FROM monthly_with_prev mwp
  JOIN country_month_stats cms
    ON cms.country_id = mwp.country_id
   AND cms.month_start = mwp.month_start
  WHERE
    (mwp.prev_month_payment_sum IS NOT NULL AND mwp.prev_month_payment_sum > 0
     AND mwp.month_payment_sum >= 3.0 * mwp.prev_month_payment_sum)
    OR
    (cms.country_avg_month_payment_sum IS NOT NULL
     AND mwp.month_payment_sum >= 2.0 * cms.country_avg_month_payment_sum)
),
top_staff_per_month AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id,
    SUM(CAST(p.p05 AS REAL)) AS staff_month_sum,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, date(p.p06, 'start of month')
      ORDER BY SUM(CAST(p.p05 AS REAL)) DESC, p.p01 DESC
    ) AS rn
  FROM pay p
  GROUP BY p.p02, date(p.p06, 'start of month'), p.p03
),
ranked_within_country AS (
  SELECT
    qm.*,
    RANK() OVER (
      PARTITION BY qm.country_id, qm.month_start
      ORDER BY qm.month_payment_sum DESC
    ) AS country_month_sum_rank,
    COUNT(*) OVER (
      PARTITION BY qm.country_id, qm.month_start
    ) AS country_month_customers_count
  FROM qualified_months qm
)
SELECT
  r.customer_id AS h01,
  r.month_start AS month,
  c.h03 || ' ' || c.h04 AS customer_name,
  r.country_name AS cty_country,
  ct.city_name AS city_name,
  r.store_id AS j01,
  st.o01 AS staff_id,
  st.o02 || ' ' || st.o03 AS staff_name,
  r.payment_count,
  ROUND(r.month_payment_sum, 2) AS month_payment_sum,
  ROUND(r.avg_check, 2) AS avg_check,
  r.distinct_payment_dates_count AS distinct_payment_dates,
  r.country_month_sum_rank,
  r.country_month_customers_count
FROM ranked_within_country r
JOIN cus c ON c.h01 = r.customer_id
JOIN adr a ON a.e01 = c.h06
JOIN cty ct ON ct.d01 = a.e05
JOIN cnt cn ON cn.c01 = ct.d03
JOIN sto s ON s.j01 = r.store_id
LEFT JOIN top_staff_per_month tsp
  ON tsp.customer_id = r.customer_id
 AND tsp.month_start = r.month_start
 AND tsp.rn = 1
LEFT JOIN stf st
  ON st.o01 = tsp.staff_id
ORDER BY
  r.month_start,
  r.country_id,
  r.country_month_sum_rank,
  r.customer_id;