WITH customer_months AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS customer_store_id,
    ci.d02 AS city,
    co.c02 AS country,
    strftime('%Y-%m', p.p06) AS month_ym,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS payment_sum
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ci.d03
  JOIN pay AS p ON p.p02 = c.h01
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    c.h01, c.h02, ci.d02, co.c02, strftime('%Y-%m', p.p06), date(p.p06, 'start of month')
),
with_rolling AS (
  SELECT
    cm.*,
    AVG(cm.payment_sum) OVER (
      PARTITION BY cm.customer_id
      ORDER BY cm.month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS prev2_months_avg_payment_sum
  FROM customer_months AS cm
),
suspicious_months AS (
  SELECT
    wr.*,
    (wr.payment_sum - wr.prev2_months_avg_payment_sum) AS deviation_from_avg
  FROM with_rolling AS wr
  WHERE wr.prev2_months_avg_payment_sum IS NOT NULL
    AND wr.payment_count >= 3
    AND wr.payment_sum >= 2.0 * wr.prev2_months_avg_payment_sum
),
store_month_totals AS (
  SELECT
    customer_store_id,
    month_start,
    PERCENT_RANK() OVER (
      PARTITION BY customer_store_id, month_start
      ORDER BY payment_sum
    ) AS pr_by_store
  FROM suspicious_months
),
suspicious_months_top10 AS (
  SELECT
    sm.*
  FROM suspicious_months AS sm
  JOIN store_month_totals AS t
    ON t.customer_store_id = sm.customer_store_id
   AND t.month_start = sm.month_start
  WHERE t.pr_by_store >= 0.90
),
store_rank AS (
  SELECT
    smt.*,
    RANK() OVER (
      PARTITION BY smt.customer_store_id, smt.month_start
      ORDER BY smt.payment_sum DESC
    ) AS store_payment_rank
  FROM suspicious_months_top10 AS smt
),
top_staff_per_client_month AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    s.o01 AS staff_id,
    SUM(p.p05) AS staff_payment_sum,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, date(p.p06, 'start of month')
      ORDER BY SUM(p.p05) DESC, s.o01
    ) AS rn
  FROM pay AS p
  JOIN stf AS s ON s.o01 = p.p03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    p.p02, date(p.p06, 'start of month'), s.o01
),
staff_top AS (
  SELECT
    t.customer_id,
    t.month_start,
    t.staff_id,
    t.staff_payment_sum
  FROM top_staff_per_client_month AS t
  WHERE t.rn = 1
)
SELECT
  sr.customer_store_id AS store_id,
  sr.city,
  sr.country,
  sr.month_ym AS payment_month,
  ROUND(sr.payment_sum, 2) AS suspicious_month_payment_sum,
  sr.payment_count,
  ROUND(sr.deviation_from_avg, 2) AS deviation_from_scrolling_avg,
  sr.store_payment_rank,
  st.staff_id AS top_staff_id,
  s.o02 || ' ' || s.o03 AS top_staff_name
FROM store_rank AS sr
JOIN staff_top AS st
  ON st.customer_id = sr.customer_id
 AND st.month_start = sr.month_start
JOIN stf AS s
  ON s.o01 = st.staff_id
ORDER BY
  sr.customer_store_id,
  sr.month_start,
  sr.store_payment_rank,
  sr.customer_id;