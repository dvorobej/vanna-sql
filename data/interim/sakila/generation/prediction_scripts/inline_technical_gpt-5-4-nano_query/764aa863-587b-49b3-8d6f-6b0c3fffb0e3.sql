WITH payment_base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    c.h02 AS home_store_id,
    cn.c01 AS country_id,
    cn.c02 AS country_name,
    ct.d01 AS city_id,
    ct.d02 AS city_name,
    date(p.p06, 'start of month') AS month_start,
    p.p05 AS payment_amount,
    p.p03 AS staff_id,
    r.q01 AS rental_id,
    i.n02 AS film_id
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS cn
    ON cn.c01 = ct.d03
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN inv AS i
    ON i.n01 = r.q03
),
monthly_customer AS (
  SELECT
    pb.customer_id,
    pb.country_name,
    pb.city_name,
    pb.home_store_id,
    pb.month_start,
    COUNT(*) AS payment_count,
    SUM(pb.payment_amount) AS month_amount,
    MAX(pb.payment_amount) AS max_single_payment,
    COUNT(DISTINCT pb.staff_id) AS distinct_staff_count,
    SUM(CASE WHEN pb.home_store_id <> s.h07_store_id THEN 1 ELSE 0 END) AS non_home_store_payment_count
  FROM payment_base AS pb
  LEFT JOIN (
    SELECT
      stf.o01 AS staff_id,
      stf.o07 AS h07_store_id
    FROM stf
  ) AS s
    ON s.staff_id = pb.staff_id
  GROUP BY
    pb.customer_id,
    pb.country_name,
    pb.city_name,
    pb.home_store_id,
    pb.month_start
),
monthly_customer_with_prev AS (
  SELECT
    mc.*,
    AVG(mc.month_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS avg_prev_3_months_amount
  FROM monthly_customer AS mc
),
monthly_customer_categories AS (
  SELECT
    pb.customer_id,
    pb.month_start,
    COUNT(DISTINCT cat.g01) AS category_count
  FROM payment_base AS pb
  JOIN flc AS fc
    ON fc.l01 = pb.film_id
  JOIN cat
    ON cat.g01 = fc.l02
  GROUP BY
    pb.customer_id,
    pb.month_start
),
qualified AS (
  SELECT
    mcwp.customer_id,
    mcwp.country_name,
    mcwp.city_name,
    mcwp.month_start,
    mcwp.month_amount,
    mcwp.payment_count,
    mcwp.max_single_payment,
    (1.0 * mcwp.non_home_store_payment_count) / NULLIF(mcwp.payment_count, 0) AS non_home_store_payment_share,
    mcwp.distinct_staff_count,
    mcc.category_count,
    mcwp.avg_prev_3_months_amount
  FROM monthly_customer_with_prev AS mcwp
  JOIN monthly_customer_categories AS mcc
    ON mcc.customer_id = mcwp.customer_id
   AND mcc.month_start = mcwp.month_start
  WHERE mcwp.avg_prev_3_months_amount IS NOT NULL
    AND mcwp.month_amount > 3.0 * mcwp.avg_prev_3_months_amount
    AND mcwp.distinct_staff_count >= 2
    AND mcc.category_count >= 3
),
ranked AS (
  SELECT
    q.*,
    RANK() OVER (
      PARTITION BY q.country_name, q.month_start
      ORDER BY q.month_amount DESC
    ) AS country_month_amount_rank
  FROM qualified AS q
)
SELECT
  customer_id,
  month_start AS month,
  country_name AS country,
  city_name AS city,
  ROUND(month_amount, 2) AS month_amount,
  payment_count,
  ROUND(max_single_payment, 2) AS max_single_payment,
  ROUND(non_home_store_payment_share, 4) AS non_home_store_payment_share,
  country_month_amount_rank
FROM ranked
ORDER BY
  month,
  country,
  country_month_amount_rank,
  customer_id;