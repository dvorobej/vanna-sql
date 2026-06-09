WITH
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    st.j01 AS store_pk,
    co.c02 AS country,
    ci.d02 AS city
  FROM cus AS c
  JOIN sto AS st
    ON st.j01 = c.h02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
),
monthly_customer_pay AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(p.p01) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS payment_sum
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
monthly_with_history AS (
  SELECT
    mcp.*,
    AVG(payment_sum) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS prev_2_month_avg_sum
  FROM monthly_customer_pay AS mcp
),
suspicious_months AS (
  SELECT
    mwh.customer_id,
    mwh.month_start,
    mwh.payment_count,
    mwh.payment_sum,
    mwh.prev_2_month_avg_sum
  FROM monthly_with_history AS mwh
  WHERE mwh.prev_2_month_avg_sum IS NOT NULL
    AND mwh.payment_count >= 3
    AND mwh.payment_sum >= 2.0 * mwh.prev_2_month_avg_sum
),
store_month_customer_sums AS (
  SELECT
    cg.store_id,
    sm.month_start,
    sm.customer_id,
    SUM(sm.payment_sum) OVER (PARTITION BY cg.store_id, sm.month_start, sm.customer_id) AS suspicious_month_sum,
    SUM(sm.payment_sum) OVER (PARTITION BY cg.store_id, sm.month_start) AS suspicious_store_month_total,
    DENSE_RANK() OVER (
      PARTITION BY cg.store_id, sm.month_start
      ORDER BY sm.payment_sum DESC
    ) AS store_month_customer_rank,
    COUNT(*) OVER (
      PARTITION BY cg.store_id, sm.month_start
    ) AS store_month_customer_count
  FROM suspicious_months AS sm
  JOIN customer_geo AS cg
    ON cg.customer_id = sm.customer_id
),
qualified_suspicious_months AS (
  SELECT
    sm.*
  FROM store_month_customer_sums AS sm
  WHERE sm.store_month_customer_rank <= CAST(CEIL(0.10 * sm.store_month_customer_count) AS INTEGER)
),
qualified_monthly_rows AS (
  SELECT
    qsm.customer_id,
    qsm.month_start,
    qsm.payment_count,
    qsm.payment_sum
  FROM qualified_suspicious_months AS qsm
  JOIN suspicious_months AS sm
    ON sm.customer_id = qsm.customer_id
   AND sm.month_start = qsm.month_start
),
qualified_customers AS (
  SELECT
    qmr.customer_id,
    MIN(cg.store_id) AS store_id,
    MIN(cg.city) AS city,
    MIN(cg.country) AS country,
    COUNT(*) AS suspicious_months_count
  FROM qualified_monthly_rows AS qmr
  JOIN customer_geo AS cg
    ON cg.customer_id = qmr.customer_id
  GROUP BY qmr.customer_id
),
top_staff_for_month AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id,
    SUM(CAST(p.p05 AS REAL)) AS staff_payment_sum,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, date(p.p06, 'start of month')
      ORDER BY SUM(CAST(p.p05 AS REAL)) DESC, p.p03
    ) AS rn
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06, 'start of month'),
    p.p03
),
rank_in_store AS (
  SELECT
    qmr.customer_id,
    qmr.month_start,
    RANK() OVER (
      PARTITION BY cg.store_id, qmr.month_start
      ORDER BY qmr.payment_sum DESC
    ) AS store_month_customer_rank
  FROM qualified_monthly_rows AS qmr
  JOIN customer_geo AS cg
    ON cg.customer_id = qmr.customer_id
)
SELECT
  cg.store_id AS store,
  cg.city,
  cg.country,
  strftime('%Y-%m', qmr.month_start) AS month,
  ROUND(qmr.payment_sum, 2) AS payment_sum,
  qmr.payment_count,
  ROUND(qmr.payment_sum - qmh.prev_2_month_avg_sum, 2) AS deviation_from_rolling_avg,
  ris.store_month_customer_rank AS store_month_rank,
  ts.o02 AS staff_first_name,
  ts.o03 AS staff_last_name,
  ts.o01 AS staff_id,
  ts.o06 AS staff_email
FROM qualified_monthly_rows AS qmr
JOIN customer_geo AS cg
  ON cg.customer_id = qmr.customer_id
JOIN monthly_with_history AS qmh
  ON qmh.customer_id = qmr.customer_id
 AND qmh.month_start = qmr.month_start
JOIN rank_in_store AS ris
  ON ris.customer_id = qmr.customer_id
 AND ris.month_start = qmr.month_start
JOIN top_staff_for_month AS tsm
  ON tsm.customer_id = qmr.customer_id
 AND tsm.month_start = qmr.month_start
 AND tsm.rn = 1
JOIN stf AS ts
  ON ts.o01 = tsm.staff_id
ORDER BY
  cg.store_id,
  cg.country,
  cg.city,
  qmr.month_start,
  qmr.payment_sum DESC;