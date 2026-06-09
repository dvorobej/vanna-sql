SELECT date('2005-01-01')
  UNION ALL
  SELECT date(month_start, '+1 month')
  FROM months
  WHERE month_start < date('2005-12-01')
),
customer_base AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS customer_store_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    ct.d02 AS customer_city,
    cn.c02 AS customer_country
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ct ON ct.d01 = a.e05
  JOIN cnt AS cn ON cn.c01 = ct.d03
),
monthly_payments AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS payment_sum,
    MAX(p.p05) AS max_payment
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
monthly_full AS (
  SELECT
    cb.customer_id,
    cb.customer_store_id,
    cb.first_name,
    cb.last_name,
    cb.customer_city,
    cb.customer_country,
    m.month_start,
    COALESCE(mp.payment_count, 0) AS payment_count,
    COALESCE(mp.payment_sum, 0) AS payment_sum,
    mp.max_payment
  FROM customer_base AS cb
  CROSS JOIN months AS m
  LEFT JOIN monthly_payments AS mp
    ON mp.customer_id = cb.customer_id
   AND mp.month_start = m.month_start
),
monthly_scored AS (
  SELECT
    mf.*,
    AVG(mf.payment_sum) OVER (
      PARTITION BY mf.customer_id
      ORDER BY mf.month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS prev2_month_avg_payment_sum,
    RANK() OVER (
      PARTITION BY mf.customer_store_id, mf.month_start
      ORDER BY mf.payment_sum DESC
    ) AS store_month_payment_rank,
    COUNT(*) OVER (
      PARTITION BY mf.customer_store_id, mf.month_start
    ) AS store_month_customer_count
  FROM monthly_full AS mf
),
sus_months AS (
  SELECT
    ms.*
  FROM monthly_scored AS ms
  WHERE ms.prev2_month_avg_payment_sum IS NOT NULL
    AND ms.payment_count >= 3
    AND ms.prev2_month_avg_payment_sum > 0
    AND ms.payment_sum >= 2.0 * ms.prev2_month_avg_payment_sum
    AND ms.store_month_payment_rank <= CEIL(0.10 * ms.store_month_customer_count)
),
sus_clients AS (
  SELECT
    customer_id,
    customer_store_id,
    customer_city,
    customer_country
  FROM sus_months
  GROUP BY
    customer_id,
    customer_store_id,
    customer_city,
    customer_country
  HAVING COUNT(*) = 10
),
top_staff_month AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id,
    SUM(p.p05) AS staff_payment_sum,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, date(p.p06, 'start of month')
      ORDER BY SUM(p.p05) DESC, p.p03
    ) AS rn
  FROM pay p
  WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06, 'start of month'),
    p.p03
)
SELECT
  sc.customer_store_id AS store_id,
  sc.customer_city AS customer_city,
  sc.customer_country AS customer_country,
  strftime('%Y-%m', sm.month_start) AS payment_month,
  ROUND(sm.payment_sum, 2) AS payment_sum,
  sm.payment_count,
  ROUND(sm.payment_sum - sm.prev2_month_avg_payment_sum, 2) AS deviation_from_scrolling_avg,
  sm.store_month_payment_rank AS store_month_rank,
  ts.staff_id,
  st.o02 AS staff_first_name,
  st.o03 AS staff_last_name,
  ROUND(ts.staff_payment_sum, 2) AS top_staff_payment_sum
FROM sus_months AS sm
JOIN sus_clients AS sc
  ON sc.customer_id = sm.customer_id
LEFT JOIN top_staff_month AS ts
  ON ts.customer_id = sm.customer_id
 AND ts.month_start = sm.month_start
 AND ts.rn = 1
LEFT JOIN stf AS st
  ON st.o01 = ts.staff_id
ORDER BY
  sc.customer_store_id,
  sm.month_start,
  sm.customer_id;