WITH
base_payments AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p03 AS staff_id,
    p.p04 AS rental_id
  FROM pay AS p
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    co.c02 AS country_name,
    ci.d02 AS city_name,
    c.h02 AS home_store_id
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
),
monthly_customer AS (
  SELECT
    bg.customer_id,
    cg.country_name,
    cg.city_name,
    cg.home_store_id,
    bg.month_start,
    COUNT(bg.payment_id) AS payment_count,
    SUM(bg.payment_amount) AS monthly_payment_sum
  FROM base_payments AS bg
  JOIN customer_geo AS cg
    ON cg.customer_id = bg.customer_id
  GROUP BY
    bg.customer_id,
    cg.country_name,
    cg.city_name,
    cg.home_store_id,
    bg.month_start
),
monthly_with_prev_avg AS (
  SELECT
    mc.*,
    AVG(mc.monthly_payment_sum) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_avg_monthly_sum
  FROM monthly_customer AS mc
),
shop_country_rank AS (
  SELECT
    mca.*,
    PERCENT_RANK() OVER (
      PARTITION BY mca.home_store_id, mca.country_name, mca.month_start
      ORDER BY mca.monthly_payment_sum DESC
    ) AS pct_rank_in_shop_country
  FROM monthly_with_prev_avg AS mca
),
return_slippage AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(
      CASE
        WHEN r.q05 IS NOT NULL
         AND (JULIANDAY(r.q05) - JULIANDAY(r.q02)) > f.i07
        THEN 1 ELSE 0
      END
    ) AS late_return_payment_count
  FROM pay AS p
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS i
    ON i.n01 = r.q03
  JOIN flm AS f
    ON f.i01 = i.n02
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
monthly_staff_counts AS (
  SELECT
    bg.customer_id,
    cg.home_store_id,
    cg.country_name,
    cg.city_name,
    bg.month_start,
    COUNT(DISTINCT bg.staff_id) AS distinct_staff_count
  FROM base_payments bg
  JOIN customer_geo cg
    ON cg.customer_id = bg.customer_id
  GROUP BY
    bg.customer_id,
    cg.home_store_id,
    cg.country_name,
    cg.city_name,
    bg.month_start
),
monthly_customer_rank_in_shop AS (
  SELECT
    sc.customer_id,
    sc.home_store_id,
    sc.country_name,
    sc.month_start,
    RANK() OVER (
      PARTITION BY sc.home_store_id, sc.month_start
      ORDER BY sc.monthly_payment_sum DESC
    ) AS customer_shop_month_rank
  FROM shop_country_rank sc
)
SELECT
  sc.customer_id,
  cg.country_name,
  cg.city_name,
  cg.home_store_id AS store_id,
  strftime('%Y-%m', sc.month_start) AS payment_month,
  ROUND(sc.monthly_payment_sum, 2) AS monthly_payment_sum,
  sc.payment_count,
  ms.distinct_staff_count,
  ROUND(
    1.0 * COALESCE(rs.late_return_payment_count, 0) / NULLIF(sc.payment_count, 0),
    4
  ) AS late_return_payment_share,
  cr.customer_shop_month_rank
FROM shop_country_rank sc
JOIN customer_geo cg
  ON cg.customer_id = sc.customer_id
LEFT JOIN monthly_staff_counts ms
  ON ms.customer_id = sc.customer_id
 AND ms.home_store_id = cg.home_store_id
 AND ms.country_name = sc.country_name
 AND ms.city_name = cg.city_name
 AND ms.month_start = sc.month_start
LEFT JOIN return_slippage rs
  ON rs.customer_id = sc.customer_id
 AND rs.month_start = sc.month_start
JOIN monthly_customer_rank_in_shop cr
  ON cr.customer_id = sc.customer_id
 AND cr.home_store_id = cg.home_store_id
 AND cr.country_name = sc.country_name
 AND cr.month_start = sc.month_start
WHERE sc.personal_avg_monthly_sum IS NOT NULL
  AND sc.personal_avg_monthly_sum > 0
  AND sc.monthly_payment_sum >= 3 * sc.personal_avg_monthly_sum
  AND sc.pct_rank_in_shop_country <= 0.05
ORDER BY
  payment_month,
  cg.country_name,
  cg.home_store_id,
  monthly_payment_sum DESC,
  sc.customer_id;