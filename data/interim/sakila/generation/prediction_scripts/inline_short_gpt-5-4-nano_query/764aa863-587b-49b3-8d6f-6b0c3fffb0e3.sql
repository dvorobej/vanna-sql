WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    ct.d01 AS city_id,
    ct.d02 AS city_name,
    cnt.c02 AS country_name,
    c.h02 AS home_store_id
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS cnt
    ON cnt.c01 = ct.d03
),
payment_film_category AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p05 AS payment_amount,
    p.p03 AS staff_id,
    r.q03 AS inventory_id,
    i.n02 AS film_id,
    fc.l02 AS category_id,
    i.n03 AS inventory_store_id
  FROM pay AS p
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS i
    ON i.n01 = r.q03
  LEFT JOIN flc AS fc
    ON fc.l01 = i.n01
  WHERE fc.l02 IS NOT NULL
),
monthly_customer AS (
  SELECT
    pfc.customer_id,
    pfc.month_start,
    SUM(pfc.payment_amount) AS month_sum,
    COUNT(*) AS payment_count,
    MAX(pfc.payment_amount) AS max_payment,
    COUNT(DISTINCT pfc.staff_id) AS distinct_staff_count,
    COUNT(DISTINCT pfc.category_id) AS distinct_category_count,
    SUM(CASE WHEN pfc.inventory_store_id <> cg.home_store_id THEN 1 ELSE 0 END) AS non_home_store_payment_count,
    COUNT(*) AS payments_for_share
  FROM payment_film_category AS pfc
  JOIN customer_geo AS cg
    ON cg.customer_id = pfc.customer_id
  GROUP BY
    pfc.customer_id,
    pfc.month_start
),
monthly_with_avg AS (
  SELECT
    mc.*,
    AVG(mc.month_sum) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS avg_prev_3_months
  FROM monthly_customer AS mc
),
qualified AS (
  SELECT
    mwa.*,
    1.0 * mwa.non_home_store_payment_count / NULLIF(mwa.payments_for_share, 0) AS non_home_store_share
  FROM monthly_with_avg AS mwa
  WHERE mwa.avg_prev_3_months IS NOT NULL
    AND mwa.month_sum > 3.0 * mwa.avg_prev_3_months
    AND mwa.distinct_staff_count >= 2
    AND mwa.distinct_category_count >= 3
),
ranked AS (
  SELECT
    q.*,
    RANK() OVER (
      PARTITION BY cg.country_name, q.month_start
      ORDER BY q.month_sum DESC
    ) AS customer_country_month_rank
  FROM qualified AS q
  JOIN customer_geo AS cg
    ON cg.customer_id = q.customer_id
)
SELECT
  r.month_start AS month,
  cg.country_name AS country,
  cg.city_name AS city,
  ROUND(r.month_sum, 2) AS month_sum,
  r.payment_count,
  ROUND(r.max_payment, 2) AS max_payment,
  ROUND(r.non_home_store_share, 4) AS non_home_store_payment_share,
  r.customer_country_month_rank AS customer_country_month_rank
FROM ranked AS r
JOIN customer_geo AS cg
  ON cg.customer_id = r.customer_id
ORDER BY
  r.month_start,
  cg.country_name,
  r.customer_country_month_rank,
  r.month_sum DESC;