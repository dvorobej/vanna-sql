WITH
base AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS customer_home_store_id,
    a.e05 AS customer_city_id,
    cn.c01 AS customer_country_id,
    p.p01 AS payment_id,
    p.p05 AS payment_amount,
    date(p.p06, 'start of month') AS month_start,
    p.p04 AS rental_id,
    p.p03 AS staff_id,
    i.n01 AS inventory_id,
    r.q03 AS inventory_movie_id,
    r.q06 AS rental_staff_id,
    inv.n03 AS rental_store_id,
    cu_city.d01 AS movie_store_city_id,
    cu_country.c01 AS movie_store_country_id,
    flc.l02 AS category_id,
    s.o07 AS staff_store_id
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS cu_city
    ON cu_city.d01 = a.e05
  JOIN cnt AS cn
    ON cn.c01 = cu_city.d03
  JOIN pay AS p
    ON p.p02 = c.h01
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN stf AS s
    ON s.o01 = p.p03
  LEFT JOIN inv
    ON inv.n01 = r.q03
  LEFT JOIN sto
    ON sto.j01 = c.h02
  JOIN flm AS f
    ON f.i01 = inv.n02
  JOIN flc
    ON flc.l01 = f.i01
  LEFT JOIN cty AS cu_city2
    ON cu_city2.d01 = inv.n04
  LEFT JOIN cnt AS cu_country
    ON cu_country.c01 = cu_city2.d03
),
monthly_customer AS (
  SELECT
    customer_id,
    month_start,
    SUM(payment_amount) AS monthly_amount,
    COUNT(*) AS payment_count,
    MAX(payment_amount) AS max_single_payment,
    AVG(monthly_amount) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_monthly_amount
  FROM base
  GROUP BY customer_id, month_start
),
customer_anomalies AS (
  SELECT
    mc.*
  FROM monthly_customer AS mc
  WHERE mc.prev_avg_monthly_amount IS NOT NULL
    AND mc.payment_count >= 5
    AND mc.monthly_amount > 3.0 * mc.prev_avg_monthly_amount
),
monthly_detail AS (
  SELECT
    ba.customer_id,
    ba.month_start,
    SUM(ba.payment_amount) AS monthly_amount,
    COUNT(*) AS payment_count,
    SUM(CASE WHEN ba.staff_store_id <> ba.customer_home_store_id THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS off_store_payment_share,
    MAX(ba.payment_amount) AS max_single_payment,
    COUNT(DISTINCT ba.staff_id) AS distinct_staff_count,
    COUNT(DISTINCT ba.rental_id) AS distinct_rental_count,
    (CASE WHEN ba.movie_store_country_id <> ba.customer_country_id OR ba.movie_store_city_id <> ba.customer_city_id THEN 1 ELSE 0 END) AS is_diff_city_or_country
  FROM base AS ba
  JOIN customer_anomalies AS ca
    ON ca.customer_id = ba.customer_id
   AND ca.month_start = ba.month_start
  GROUP BY ba.customer_id, ba.month_start
),
month_rank_by_customer AS (
  SELECT
    md.*,
    RANK() OVER (
      PARTITION BY md.customer_id
      ORDER BY md.monthly_amount DESC
    ) AS month_amount_rank_inside_customer
  FROM monthly_detail AS md
),
categories_per_month AS (
  SELECT
    ba.customer_id,
    ba.month_start,
    GROUP_CONCAT(DISTINCT CAST(ba.category_id AS TEXT), ',') AS category_list
  FROM base AS ba
  JOIN customer_anomalies AS ca
    ON ca.customer_id = ba.customer_id
   AND ca.month_start = ba.month_start
  GROUP BY ba.customer_id, ba.month_start
)
SELECT
  mrd.customer_id AS h01,
  mrd.month_start AS month,
  ROUND(mrd.monthly_amount, 2) AS month_payment_sum,
  mrd.payment_count,
  ROUND(mrd.off_store_payment_share, 4) AS off_store_payment_share,
  ROUND(mrd.max_single_payment, 2) AS max_single_payment,
  mrd.month_amount_rank_inside_customer,
  cpm.category_list AS categories_g02
FROM month_rank_by_customer AS mrd
JOIN categories_per_month AS cpm
  ON cpm.customer_id = mrd.customer_id
 AND cpm.month_start = mrd.month_start
ORDER BY
  mrd.customer_id,
  mrd.month_start,
  mrd.month_amount_rank_inside_customer;