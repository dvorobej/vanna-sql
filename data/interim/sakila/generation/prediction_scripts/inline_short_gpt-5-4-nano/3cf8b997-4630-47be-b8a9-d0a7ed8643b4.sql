WITH monthly AS (
  SELECT
    c.h01 AS customer_id,
    st.j01 AS store_id,
    st.j02 AS store_name,
    ci.d02 AS city,
    co.d02 AS country,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS month_amount,
    MAX(p.p05) AS max_payment,
    COUNT(DISTINCT p.p03) AS distinct_staff_count
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN stf AS sf
    ON sf.o01 = p.p03
  JOIN sto AS st
    ON st.j01 = sf.o07
  JOIN adr AS ca
    ON ca.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = ca.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    c.h01, st.j01, st.j02, ci.d02, co.d02, date(p.p06, 'start of month')
),
with_prev AS (
  SELECT
    m.*,
    AVG(m2.month_amount) AS prev2_avg_amount
  FROM monthly AS m
  LEFT JOIN monthly AS m2
    ON m2.customer_id = m.customer_id
   AND m2.store_id = m.store_id
   AND m2.month_start BETWEEN date(m.month_start, '-2 months') AND date(m.month_start, '-1 months')
  GROUP BY
    m.customer_id, m.store_id, m.store_name, m.city, m.country, m.month_start,
    m.payment_count, m.month_amount, m.max_payment, m.distinct_staff_count
),
filtered AS (
  SELECT
    wp.*,
    (wp.month_amount / NULLIF(wp.prev2_avg_amount, 0)) AS deviation_multiple,
    RANK() OVER (
      PARTITION BY wp.store_id, wp.month_start
      ORDER BY wp.month_amount DESC
    ) AS store_month_rank,
    COUNT(*) OVER (
      PARTITION BY wp.store_id, wp.month_start
    ) AS store_month_total
  FROM with_prev AS wp
  WHERE wp.payment_count >= 3
    AND wp.prev2_avg_amount IS NOT NULL
    AND wp.month_amount >= 2.0 * wp.prev2_avg_amount
),
store_top10 AS (
  SELECT *
  FROM filtered
  WHERE store_month_total > 0
    AND store_month_rank <= CAST(store_month_total * 0.10 AS INT)
),
staff_best AS (
  SELECT
    c.h01 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(p.p05) AS staff_best_amount,
    p.p03 AS staff_id,
    ROW_NUMBER() OVER (
      PARTITION BY c.h01, date(p.p06, 'start of month')
      ORDER BY SUM(p.p05) DESC
    ) AS rn
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY c.h01, date(p.p06, 'start of month'), p.p03
)
SELECT
  st.store_name AS store,
  st.city AS city,
  st.country AS country,
  strftime('%Y-%m', st.month_start) AS month,
  ROUND(st.month_amount, 2) AS month_sum,
  st.payment_count AS payment_count,
  ROUND((st.month_amount - st.prev2_avg_amount), 2) AS deviation_amount,
  st.deviation_multiple AS deviation_multiple,
  st.store_month_rank AS month_rank,
  s.o02 AS staff_first_name,
  s.o03 AS staff_last_name,
  sb.staff_best_amount AS staff_best_payment_amount
FROM store_top10 AS st
JOIN staff_best AS sb
  ON sb.customer_id = st.customer_id
 AND sb.month_start = st.month_start
 AND sb.rn = 1
JOIN stf AS s
  ON s.o01 = sb.staff_id
ORDER BY
  st.store_id,
  st.month_start,
  st.store_month_rank,
  st.customer_id;