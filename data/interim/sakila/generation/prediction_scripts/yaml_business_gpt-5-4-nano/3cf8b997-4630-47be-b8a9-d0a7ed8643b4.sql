WITH monthly AS (
  SELECT
    p.p02 AS customer_id,
    c.h02 AS store_id,
    strftime('%Y-%m', p.p06) AS month_key,
    date(p.p06, 'start of month') AS month_start,
    COUNT(p.p01) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS payment_sum
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    c.h02,
    strftime('%Y-%m', p.p06),
    date(p.p06, 'start of month')
),
hist AS (
  SELECT
    m.*,
    AVG(payment_sum) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS avg_prev_2_months
  FROM monthly AS m
),
susp_months AS (
  SELECT
    h.*,
    RANK() OVER (
      PARTITION BY store_id, month_start
      ORDER BY payment_sum DESC
    ) AS store_month_rank,
    COUNT(*) OVER (
      PARTITION BY store_id, month_start
    ) AS store_month_cnt
  FROM hist AS h
  WHERE avg_prev_2_months IS NOT NULL
    AND payment_count >= 3
    AND payment_sum >= 2.0 * avg_prev_2_months
),
flagged_customers AS (
  -- условие "в каждом месяце 2005 года": оставляем только тех, у кого есть все месяцы 2005
  SELECT
    customer_id,
    store_id
  FROM susp_months
  GROUP BY customer_id, store_id
  HAVING COUNT(DISTINCT month_start) = 12
),
top10pct_store_month AS (
  SELECT
    sm.*,
    CASE
      WHEN store_month_rank <= CAST( (store_month_cnt * 0.10) + 0.999999 AS INT ) THEN 1
      ELSE 0
    END AS is_top_10pct_in_store_month
  FROM susp_months AS sm
  JOIN flagged_customers AS fc
    ON fc.customer_id = sm.customer_id
   AND fc.store_id = sm.store_id
),
top10 AS (
  SELECT *
  FROM top10pct_store_month
  WHERE is_top_10pct_in_store_month = 1
),
staff_max AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS month_key,
    s.o01 AS staff_id,
    SUM(p.p05) AS staff_month_sum,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, strftime('%Y-%m', p.p06)
      ORDER BY SUM(p.p05) DESC
    ) AS rn
  FROM pay AS p
  JOIN stf AS s
    ON s.o01 = p.p03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06),
    s.o01
)
SELECT
  t.customer_id,
  c.h03 AS customer_first_name,
  c.h04 AS customer_last_name,
  t.store_id,
  strftime('%Y-%m', t.month_start) AS month,
  ROUND(t.payment_sum, 2) AS payment_sum,
  t.payment_count,
  ROUND(t.payment_sum - t.avg_prev_2_months, 2) AS deviation_from_moving_avg,
  t.store_month_rank AS rank_in_store_month,
  stf.o02 AS top_staff_first_name,
  stf.o03 AS top_staff_last_name
FROM top10 AS t
JOIN cus AS c
  ON c.h01 = t.customer_id
LEFT JOIN adr AS a
  ON a.e01 = c.h06
LEFT JOIN cty AS ci
  ON ci.d01 = a.e05
LEFT JOIN cnt AS co
  ON co.c01 = ci.d03
LEFT JOIN staff_max AS sm
  ON sm.customer_id = t.customer_id
 AND sm.month_key = t.month_key
 AND sm.rn = 1
LEFT JOIN stf AS stf
  ON stf.o01 = sm.staff_id
ORDER BY
  t.store_id,
  t.month_start,
  t.payment_sum DESC,
  t.customer_id;