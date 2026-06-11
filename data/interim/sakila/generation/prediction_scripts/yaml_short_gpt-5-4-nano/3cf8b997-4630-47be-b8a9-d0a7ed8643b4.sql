WITH monthly_customer_payment AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(p.p05) AS month_amount,
    COUNT(p.p01) AS payment_count,
    MAX(p.p05) AS max_payment
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
monthly_customer_with_avg AS (
  SELECT
    mcp.*,
    AVG(month_amount) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS prev_2_months_avg
  FROM monthly_customer_payment AS mcp
),
qualifying_customer_months AS (
  SELECT
    customer_id,
    month_start,
    month_amount,
    payment_count,
    prev_2_months_avg,
    (month_amount - prev_2_months_avg) AS deviation,
    CASE
      WHEN prev_2_months_avg > 0 THEN month_amount / prev_2_months_avg
      ELSE NULL
    END AS ratio_to_prev_avg
  FROM monthly_customer_with_avg
  WHERE prev_2_months_avg IS NOT NULL
    AND payment_count >= 3
    AND month_amount >= 2.0 * prev_2_months_avg
),
customer_months_all_req AS (
  SELECT
    customer_id,
    COUNT(*) AS qualifying_months_cnt
  FROM qualifying_customer_months
  GROUP BY customer_id
),
months_needed AS (
  SELECT 10 AS need_months
),
top10pct_months_in_store AS (
  SELECT
    t.*,
    PERCENT_RANK() OVER (PARTITION BY t.store_id, t.month_start ORDER BY t.month_amount DESC) AS prnk
  FROM (
    SELECT
      qm.month_start,
      qm.customer_id,
      qm.month_amount,
      qm.payment_count,
      qm.deviation,
      qm.prev_2_months_avg,
      s.o07 AS store_id,
      stf.o02 AS max_staff_first_name,
      stf.o03 AS max_staff_last_name,
      stf.o01 AS max_staff_id
    FROM qualifying_customer_months AS qm
    JOIN pay AS p
      ON p.p02 = qm.customer_id
     AND date(p.p06, 'start of month') = qm.month_start
    JOIN stf AS stf
      ON stf.o01 = p.p03
    JOIN stf AS s
      ON s.o01 = p.p03
    JOIN (
      SELECT
        p2.p02 AS customer_id,
        date(p2.p06, 'start of month') AS month_start,
        MAX(p2.p05) AS mx
      FROM pay AS p2
      WHERE p2.p06 >= '2005-01-01' AND p2.p06 < '2006-01-01'
      GROUP BY
        p2.p02,
        date(p2.p06, 'start of month')
    ) AS mx
      ON mx.customer_id = p.p02
     AND mx.month_start = date(p.p06, 'start of month')
     AND mx.mx = p.p05
  ) AS t
),
qualified_top10 AS (
  SELECT
    t.*,
    DENSE_RANK() OVER (PARTITION BY t.store_id, t.month_start ORDER BY t.month_amount DESC) AS store_month_rank
  FROM top10pct_months_in_store AS t
  WHERE t.prnk >= 0.9
)
SELECT
  c.h03 || ' ' || c.h04 AS customer_name,
  st.name_store AS store_name,
  city.d02 AS city,
  country.d02 AS country,
  strftime('%Y-%m', qt.month_start) AS month,
  ROUND(qt.month_amount, 2) AS total_amount,
  qt.payment_count,
  ROUND(qt.deviation, 2) AS deviation,
  qt.store_month_rank AS rank_in_store_month,
  qt.max_staff_first_name || ' ' || qt.max_staff_last_name AS top_staff_name,
  qt.max_staff_id AS top_staff_id
FROM qualified_top10 AS qt
JOIN cus AS c
  ON c.h01 = qt.customer_id
JOIN sto AS st
  ON st.j01 = qt.store_id
JOIN adr AS a_c
  ON a_c.e01 = c.h06
JOIN cty AS city
  ON city.d01 = a_c.e05
JOIN cnt AS country
  ON country.c01 = city.d03
WHERE qt.customer_id IN (
  SELECT cm.customer_id
  FROM customer_months_all_req AS cm
  CROSS JOIN months_needed AS mn
  WHERE cm.qualifying_months_cnt >= mn.need_months
)
ORDER BY
  qt.store_id,
  qt.month_start,
  qt.month_amount DESC,
  qt.customer_id;