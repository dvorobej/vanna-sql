WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_fio,
    cnt.c02 AS country_name,
    cty.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty
    ON cty.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = cty.d03
),
payments_base AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p01 AS payment_id,
    CAST(p.p05 AS REAL) AS amount,
    p.p03 AS staff_id,
    s.o07 AS staff_store_id,
    p.p06
  FROM pay AS p
  JOIN stf AS s
    ON s.o01 = p.p03
),
monthly AS (
  SELECT
    pb.customer_id,
    pb.month_start,
    COUNT(pb.payment_id) AS payment_count,
    SUM(pb.amount) AS month_amount,
    MAX(pb.amount) AS max_payment,
    SUM(CASE WHEN pb.amount > 0 THEN 1 ELSE 0 END) AS pos_payment_count,
    1.0 * MAX(pb.amount) / NULLIF(SUM(pb.amount), 0) AS max_payment_share,
    COUNT(DISTINCT pb.staff_id) AS staff_count,
    COUNT(DISTINCT pb.staff_store_id) AS store_count,
    COUNT(DISTINCT date(pb.p06)) AS distinct_payment_days
  FROM payments_base AS pb
  GROUP BY
    pb.customer_id,
    pb.month_start
),
monthly_with_avg AS (
  SELECT
    m.*,
    AVG(month_amount) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_months_avg_amount,
    RANK() OVER (
      PARTITION BY customer_id
      ORDER BY month_amount DESC
    ) AS customer_month_rank
  FROM monthly AS m
),
country_month_rank AS (
  SELECT
    mwa.*,
    DENSE_RANK() OVER (
      PARTITION BY cg.country_name, mwa.month_start
      ORDER BY mwa.month_amount DESC
    ) AS country_month_amount_rank
  FROM monthly_with_avg AS mwa
  JOIN customer_geo AS cg
    ON cg.customer_id = mwa.customer_id
)
SELECT
  mwa.month_start,
  cg.customer_fio AS fio,
  cg.country_name AS country,
  cg.city_name AS city,
  mwa.payment_count,
  ROUND(mwa.month_amount, 2) AS payment_sum,
  ROUND(mwa.max_payment, 2) AS max_payment,
  ROUND(mwa.max_payment_share, 4) AS max_payment_share,
  mwa.staff_count AS staff_count,
  mwa.store_count AS store_count,
  cmr.country_month_amount_rank AS rank_in_country
FROM country_month_rank AS cmr
JOIN customer_geo AS cg
  ON cg.customer_id = cmr.customer_id
WHERE cmr.prev_months_avg_amount IS NOT NULL
  AND cmr.prev_months_avg_amount > 0
  AND cmr.month_amount > 3.0 * cmr.prev_months_avg_amount
  AND cmr.payment_count >= 3
  AND cmr.distinct_payment_days >= 3
ORDER BY
  cmr.month_start,
  cg.country_name,
  rank_in_country,
  cmr.customer_id;