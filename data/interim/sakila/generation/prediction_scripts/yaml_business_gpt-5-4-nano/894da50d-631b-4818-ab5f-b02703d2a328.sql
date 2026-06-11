WITH payments_2005 AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p04 AS rental_id,
    CAST(p.p05 AS REAL) AS payment_amount,
    date(p.p06, 'start of month') AS month_start,
    p.p06 AS payment_date
  FROM pay AS p
  WHERE p.p04 IS NOT NULL
),
customer_profile AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS home_store_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cn.c01 AS customer_country_id,
    ct.d02 AS customer_city_name,
    cn.c02 AS customer_country_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ct ON ct.d01 = a.e05
  JOIN cnt AS cn ON cn.c01 = ct.d03
),
payment_with_store_and_item AS (
  SELECT
    pr.customer_id,
    pr.first_name,
    pr.last_name,
    pr.home_store_id,
    pr.customer_country_id,
    pr.customer_city_name,
    pr.payment_id,
    pr.month_start,
    pr.payment_amount,
    pr.payment_date,
    s.o07 AS staff_store_id,
    r.q01 AS rental_item_id,
    i.n01 AS inventory_id,
    f.i01 AS film_id,
    fc.l02 AS category_id,
    ca.g02 AS category_name
  FROM payments_2005 AS pr
  JOIN stf AS s ON s.o01 = pr.staff_id
  JOIN ren AS r ON r.q01 = pr.rental_id
  JOIN inv AS i ON i.n01 = r.q03
  JOIN flm AS f ON f.i01 = i.n02
  JOIN flc AS fc ON fc.l01 = f.i01
  JOIN cat AS ca ON ca.g01 = fc.l02
),
monthly_customer AS (
  SELECT
    p.customer_id,
    p.first_name,
    p.last_name,
    p.month_start,
    p.home_store_id,
    COUNT(DISTINCT p.payment_id) AS payment_count,
    SUM(p.payment_amount) AS month_total_amount,
    MAX(p.payment_amount) AS max_payment_amount,
    SUM(CASE WHEN p.staff_store_id <> p.home_store_id THEN 1 ELSE 0 END) * 1.0
      / NULLIF(COUNT(DISTINCT p.payment_id), 0) AS foreign_store_share
  FROM payment_with_store_and_item AS p
  GROUP BY
    p.customer_id, p.first_name, p.last_name, p.month_start, p.home_store_id
),
monthly_history AS (
  SELECT
    mc.*,
    AVG(mc.month_total_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_amount
  FROM monthly_customer AS mc
),
alerts AS (
  SELECT
    mh.*
  FROM monthly_history AS mh
  WHERE mh.prev_avg_amount IS NOT NULL
    AND mh.prev_avg_amount > 0
    AND mh.payment_count >= 5
    AND mh.month_total_amount > 3.0 * mh.prev_avg_amount
),
category_agg AS (
  SELECT
    p.customer_id,
    p.month_start,
    p.category_name,
    SUM(p.payment_amount) AS category_amount,
    DENSE_RANK() OVER (
      PARTITION BY p.customer_id, p.month_start
      ORDER BY SUM(p.payment_amount) DESC
    ) AS category_rank
  FROM payment_with_store_and_item AS p
  GROUP BY p.customer_id, p.month_start, p.category_name
),
top_categories AS (
  SELECT
    ca.customer_id,
    ca.month_start,
    GROUP_CONCAT(ca.category_name, ', ') AS top_categories
  FROM category_agg AS ca
  WHERE ca.category_rank <= 3
  GROUP BY ca.customer_id, ca.month_start
),
month_rank_within_customer AS (
  SELECT
    a.customer_id,
    a.month_start,
    RANK() OVER (
      PARTITION BY a.customer_id
      ORDER BY a.month_total_amount DESC
    ) AS month_spend_rank_within_customer
  FROM alerts AS a
)
SELECT
  a.customer_id,
  a.first_name,
  a.last_name,
  cp.customer_country_name AS customer_country,
  cp.customer_city_name AS customer_city,
  a.month_start AS month,
  ROUND(a.month_total_amount, 2) AS month_total_amount,
  a.payment_count,
  ROUND(a.max_payment_amount, 2) AS max_payment_amount,
  ROUND(a.foreign_store_share, 4) AS foreign_store_payment_share,
  mr.month_spend_rank_within_customer AS month_rank_within_customer,
  tc.top_categories AS main_categories
FROM alerts AS a
JOIN customer_profile AS cp
  ON cp.customer_id = a.customer_id
JOIN month_rank_within_customer AS mr
  ON mr.customer_id = a.customer_id
 AND mr.month_start = a.month_start
LEFT JOIN top_categories AS tc
  ON tc.customer_id = a.customer_id
 AND tc.month_start = a.month_start
ORDER BY
  a.month_start,
  a.customer_id;