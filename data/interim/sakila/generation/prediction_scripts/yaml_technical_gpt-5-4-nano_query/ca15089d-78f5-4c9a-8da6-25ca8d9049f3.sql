WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_fio,
    co.c02 AS country_name,
    ci.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ci.d03
),
month_payments AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS payment_month,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS monthly_amount,
    MAX(p.p05) AS max_payment_amount,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT COALESCE(s.o07, -1)) AS store_count,
    COUNT(DISTINCT date(p.p06)) AS distinct_payment_days
  FROM pay AS p
  LEFT JOIN stf AS s ON s.o01 = p.p03
  WHERE p.p04 IS NOT NULL
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06)
),
with_history AS (
  SELECT
    mp.*,
    AVG(mp.monthly_amount) OVER (
      PARTITION BY mp.customer_id
      ORDER BY mp.payment_month
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_avg_prev_months
  FROM month_payments AS mp
),
filtered AS (
  SELECT
    wh.*,
    (wh.max_payment_amount * 1.0 / NULLIF(wh.monthly_amount, 0)) AS max_payment_share
  FROM with_history AS wh
  WHERE wh.personal_avg_prev_months IS NOT NULL
    AND wh.personal_avg_prev_months > 0
    AND wh.monthly_amount >= 3.0 * wh.personal_avg_prev_months
    AND wh.payment_count >= 3
    AND wh.distinct_payment_days >= 3
    AND (wh.staff_count >= 2 OR wh.store_count >= 2)
),
ranked AS (
  SELECT
    f.*,
    RANK() OVER (
      PARTITION BY cg.country_name, f.payment_month
      ORDER BY f.monthly_amount DESC
    ) AS customer_country_month_rank
  FROM filtered AS f
  JOIN customer_geo AS cg ON cg.customer_id = f.customer_id
)
SELECT
  r.payment_month AS month,
  cg.customer_fio AS customer_fio,
  cg.country_name AS country,
  cg.city_name AS city,
  r.payment_count AS payment_count,
  ROUND(r.monthly_amount, 2) AS monthly_sum,
  ROUND(r.max_payment_amount, 2) AS max_payment,
  ROUND(r.max_payment_share, 4) AS max_payment_share_in_month,
  r.staff_count AS staff_count,
  r.store_count AS store_count,
  r.customer_country_month_rank AS country_month_rank
FROM ranked AS r
JOIN customer_geo AS cg ON cg.customer_id = r.customer_id
ORDER BY
  cg.country_name,
  r.payment_month,
  r.customer_country_month_rank,
  r.customer_id;