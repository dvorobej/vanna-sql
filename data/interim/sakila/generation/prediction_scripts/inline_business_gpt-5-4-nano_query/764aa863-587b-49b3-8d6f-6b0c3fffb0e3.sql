WITH payment_base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p05 AS payment_amount,
    date(p.p06, 'start of month') AS month_start,
    c.h02 AS home_store_id,
    cnt.c01 AS country_id,
    cnt.c02 AS country_name,
    ct.d02 AS city_name,
    i.n02 AS film_id,
    r.q01 AS rental_id
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS cnt
    ON cnt.c01 = ct.d03
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS i
    ON i.n01 = r.q03
),
monthly_customer AS (
  SELECT
    pb.customer_id,
    pb.country_name,
    pb.city_name,
    pb.month_start,
    SUM(pb.payment_amount) AS month_amount,
    COUNT(pb.payment_id) AS payment_count,
    MAX(pb.payment_amount) AS max_payment,
    COUNT(DISTINCT pb.staff_id) AS staff_count,
    COUNT(*) AS payment_rows,
    SUM(CASE WHEN i.n03 <> pb.home_store_id THEN 1 ELSE 0 END) AS not_home_store_payment_count
  FROM payment_base AS pb
  LEFT JOIN ren AS r
    ON r.q01 = pb.rental_id
  LEFT JOIN inv AS i
    ON i.n01 = r.q03
  GROUP BY
    pb.customer_id,
    pb.country_name,
    pb.city_name,
    pb.month_start
),
monthly_with_prev_avg AS (
  SELECT
    mc.*,
    AVG(mc.month_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS prev_3_months_avg_amount
  FROM monthly_customer AS mc
),
monthly_categories AS (
  SELECT
    pb.customer_id,
    pb.month_start,
    COUNT(DISTINCT fc.l02) AS category_count
  FROM payment_base AS pb
  JOIN ren AS r
    ON r.q01 = pb.rental_id
  JOIN inv AS i
    ON i.n01 = r.q03
  JOIN flc AS fc
    ON fc.l01 = i.n02
  GROUP BY
    pb.customer_id,
    pb.month_start
),
monthly_rank AS (
  SELECT
    mpa.*,
    RANK() OVER (
      PARTITION BY mpa.country_name, mpa.month_start
      ORDER BY mpa.month_amount DESC
    ) AS country_month_amount_rank
  FROM monthly_with_prev_avg AS mpa
)
SELECT
  mr.month_start AS month,
  mr.country_name AS country,
  mr.city_name AS city,
  ROUND(mr.month_amount, 2) AS payment_sum,
  mr.payment_count,
  ROUND(mr.max_payment, 2) AS max_single_payment,
  ROUND(1.0 * mr.not_home_store_payment_count / NULLIF(mr.payment_rows, 0), 4) AS not_home_store_payment_share,
  mr.country_month_amount_rank AS country_month_payment_rank
FROM monthly_rank AS mr
JOIN monthly_with_prev_avg AS mprev
  ON mprev.customer_id = mr.customer_id
 AND mprev.month_start = mr.month_start
 AND mprev.country_name = mr.country_name
JOIN monthly_categories AS cat
  ON cat.customer_id = mr.customer_id
 AND cat.month_start = mr.month_start
WHERE mprev.prev_3_months_avg_amount IS NOT NULL
  AND mprev.month_amount > 3.0 * mprev.prev_3_months_avg_amount
  AND mprev.staff_count >= 2
  AND cat.category_count >= 3
ORDER BY
  mr.month_start,
  mr.country_name,
  mr.country_month_amount_rank,
  mr.customer_id;