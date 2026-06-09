WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    cnt.c01 AS country_id,
    cnt.c02 AS country,
    c.h03 AS first_name,
    c.h04 AS last_name,
    adr.e01 AS address_id
  FROM cus AS c
  JOIN adr ON adr.e01 = c.h06
  JOIN cty ci ON ci.d01 = adr.e05
  JOIN cnt ON cnt.c01 = ci.d03
),
monthly_customer_staff AS (
  SELECT
    p.p02 AS customer_id,
    cg.country_id,
    cg.country,
    cg.store_id,
    p.p03 AS staff_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(CAST(p.p05 AS REAL)) AS month_amount,
    COUNT(*) AS payment_count
  FROM pay p
  JOIN customer_geo cg
    ON cg.customer_id = p.p02
  GROUP BY
    p.p02,
    cg.country_id,
    cg.country,
    cg.store_id,
    p.p03,
    date(p.p06, 'start of month')
),
monthly_customer_staff_ranked AS (
  SELECT
    m.*,
    RANK() OVER (
      PARTITION BY m.country_id, m.month_start
      ORDER BY m.month_amount DESC
    ) AS country_month_amount_rank,
    AVG(m.month_amount) OVER (
      PARTITION BY m.country_id, m.month_start
    ) AS country_month_avg_amount,
    LAG(m.month_amount) OVER (
      PARTITION BY m.country_id, m.customer_id, m.store_id, m.staff_id
      ORDER BY m.month_start
    ) AS prev_month_amount
  FROM monthly_customer_staff m
),
best_customer_per_staff_month AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY country_id, month_start, store_id, staff_id
      ORDER BY month_amount DESC
    ) AS rn_staff_best
  FROM monthly_customer_staff_ranked
)
SELECT
  bc.customer_id,
  bc.first_name,
  bc.last_name,
  bc.country,
  bc.store_id,
  bc.staff_id,
  bc.month_start AS month,
  ROUND(bc.month_amount, 2) AS month_amount,
  bc.payment_count,
  bc.country_month_amount_rank,
  ROUND(bc.prev_month_amount, 2) AS prev_month_amount,
  ROUND(bc.month_amount - bc.prev_month_amount, 2) AS deviation_from_prev_month,
  ROUND(bc.country_month_avg_amount, 2) AS country_month_avg_amount,
  ROUND(bc.month_amount - bc.country_month_avg_amount, 2) AS deviation_from_country_avg
FROM (
  SELECT
    b.customer_id,
    cg.first_name,
    cg.last_name,
    b.country_id,
    b.country,
    b.store_id,
    b.staff_id,
    b.month_start,
    b.month_amount,
    b.payment_count,
    b.country_month_amount_rank,
    b.country_month_avg_amount,
    b.prev_month_amount
  FROM best_customer_per_staff_month b
  JOIN customer_geo cg
    ON cg.customer_id = b.customer_id
  WHERE b.rn_staff_best = 1
) AS bc
ORDER BY
  bc.country,
  bc.month_start,
  bc.store_id,
  bc.staff_id,
  bc.country_month_amount_rank;