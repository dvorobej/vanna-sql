WITH payments_2005 AS (
  SELECT
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p06,
    date(p.p06, 'start of month') AS month_start,
    CAST(p.p05 AS REAL) AS amount
  FROM pay AS p
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    co.c01 AS country_id
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ci.d03
),
monthly_staff AS (
  SELECT
    cg.country_id,
    cg.store_id,
    p2005.customer_id,
    p2005.staff_id,
    p2005.month_start,
    SUM(p2005.amount) AS monthly_amount,
    COUNT(*) AS payment_count
  FROM payments_2005 AS p2005
  JOIN customer_geo AS cg
    ON cg.customer_id = p2005.customer_id
  WHERE p2005.p06 >= '2005-01-01'
    AND p2005.p06 <  '2006-01-01'
  GROUP BY
    cg.country_id,
    cg.store_id,
    p2005.customer_id,
    p2005.staff_id,
    p2005.month_start
),
top_staff_per_month AS (
  SELECT
    ms.*,
    DENSE_RANK() OVER (
      PARTITION BY ms.country_id, ms.store_id, ms.customer_id, ms.month_start
      ORDER BY ms.monthly_amount DESC
    ) AS customer_staff_rank_in_month
  FROM monthly_staff AS ms
),
country_month_avg AS (
  SELECT
    cg.country_id,
    ms.month_start,
    AVG(ms.monthly_amount) AS country_avg_monthly_amount
  FROM monthly_staff AS ms
  JOIN customer_geo AS cg
    ON cg.customer_id = ms.customer_id
  GROUP BY cg.country_id, ms.month_start
),
customer_month_country AS (
  SELECT
    ts.country_id,
    ts.store_id,
    ts.customer_id,
    ts.staff_id,
    ts.month_start,
    ts.monthly_amount,
    ts.payment_count,
    LAG(ts.monthly_amount) OVER (
      PARTITION BY ts.country_id, ts.store_id, ts.customer_id
      ORDER BY ts.month_start
    ) AS prev_month_amount,
    cma.country_avg_monthly_amount
  FROM top_staff_per_month AS ts
  JOIN country_month_avg AS cma
    ON cma.country_id = ts.country_id
   AND cma.month_start = ts.month_start
  WHERE ts.customer_staff_rank_in_month = 1
),
ranked_by_staff_in_country AS (
  SELECT
    cmc.*,
    DENSE_RANK() OVER (
      PARTITION BY cmc.country_id, cmc.month_start, cmc.store_id
      ORDER BY cmc.monthly_amount DESC
    ) AS staff_rank_in_country_month_store
  FROM customer_month_country AS cmc
)
SELECT
  r.country_id,
  r.store_id,
  r.customer_id,
  r.staff_id,
  r.month_start AS month,
  ROUND(r.monthly_amount, 2) AS monthly_amount,
  r.payment_count,
  ROUND(r.prev_month_amount, 2) AS prev_month_amount,
  ROUND(r.monthly_amount - r.prev_month_amount, 2) AS deviation_from_prev_month,
  ROUND(r.country_avg_monthly_amount, 2) AS country_avg_monthly_amount,
  ROUND(r.monthly_amount - r.country_avg_monthly_amount, 2) AS deviation_from_country_avg,
  ROUND(
    CASE WHEN r.country_avg_monthly_amount = 0 THEN NULL
         ELSE (r.monthly_amount / r.country_avg_monthly_amount)
    END,
    4
  ) AS ratio_to_country_avg,
  r.staff_rank_in_country_month_store
FROM ranked_by_staff_in_country AS r
ORDER BY
  r.country_id,
  r.month_start,
  r.store_id,
  r.staff_rank_in_country_month_store,
  r.customer_id;