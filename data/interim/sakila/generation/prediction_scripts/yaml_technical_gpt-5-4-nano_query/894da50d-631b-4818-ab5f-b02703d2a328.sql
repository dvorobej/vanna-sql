WITH payment_base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    c.h02 AS customer_home_store_id,
    cp.city_id AS customer_city_id,
    cp.country_id AS customer_country_id,
    date(p.p06, 'start of month') AS month_start,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p03 AS staff_id,
    s.o01 AS payment_store_id,
    r.q01 AS rental_id,
    i.n02 AS film_id
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN city_prov cp
    ON cp.city_id = a.e05
  JOIN stf AS s
    ON s.o01 = p.p03
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN inv AS i
    ON i.n01 = r.q03
),
monthly_customer AS (
  SELECT
    customer_id,
    month_start,
    SUM(payment_amount) AS month_payment_sum,
    COUNT(*) AS payment_count,
    MAX(payment_amount) AS max_payment,
    -- доля платежей, где сотрудник из "чужого" магазина относительно домашнего магазина клиента
    SUM(CASE WHEN payment_store_id <> customer_home_store_id THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS off_home_store_payment_share,
    -- доля платежей, где город/страна адреса клиента отличались от магазина, выдавшего копию (через inv/sto не можем, поэтому считаем по сотруднику)
    SUM(CASE
          WHEN payment_store_id <> customer_home_store_id
           THEN 1 ELSE 0
        END) * 1.0 / COUNT(*) AS off_home_store_city_country_payment_share
  FROM payment_base
  GROUP BY customer_id, month_start
),
payment_with_history AS (
  SELECT
    mc.*,
    AVG(mc.month_payment_sum) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_avg_month_payment_sum,
    COUNT(*) OVER (PARTITION BY mc.customer_id) AS customer_months_count
  FROM monthly_customer mc
),
suspicious_months AS (
  SELECT *
  FROM payment_with_history
  WHERE prev_avg_month_payment_sum IS NOT NULL
    AND month_payment_sum > 3.0 * prev_avg_month_payment_sum
    AND payment_count >= 5
),
customer_month_rank AS (
  SELECT
    sm.customer_id,
    sm.month_start,
    RANK() OVER (
      PARTITION BY sm.customer_id
      ORDER BY sm.month_payment_sum DESC
    ) AS month_payment_rank_within_customer
  FROM suspicious_months sm
),
monthly_staff_count AS (
  SELECT
    pb.customer_id,
    pb.month_start,
    COUNT(DISTINCT pb.staff_id) AS distinct_staff_count,
    COUNT(DISTINCT pb.payment_store_id) AS distinct_payment_stores_count
  FROM payment_base pb
  GROUP BY pb.customer_id, pb.month_start
),
top_categories AS (
  SELECT
    pb.customer_id,
    pb.month_start,
    ca.g02 AS category_name,
    SUM(pb.payment_amount) AS category_amount,
    ROW_NUMBER() OVER (
      PARTITION BY pb.customer_id, pb.month_start
      ORDER BY SUM(pb.payment_amount) DESC, ca.g02
    ) AS cat_rn
  FROM payment_base pb
  JOIN flc fc
    ON fc.l01 = pb.film_id
  JOIN cat ca
    ON ca.g01 = fc.l02
  GROUP BY pb.customer_id, pb.month_start, ca.g02
),
top_category_list AS (
  SELECT
    tc.customer_id,
    tc.month_start,
    GROUP_CONCAT(tc.category_name, ', ') AS categories_for_main_spend
  FROM top_categories tc
  WHERE tc.cat_rn <= 5
  GROUP BY tc.customer_id, tc.month_start
)
SELECT
  sm.month_start AS month,
  sm.customer_id,
  sm.customer_id,
  cb.customer_name,
  sm.month_payment_sum AS total_payment_sum,
  sm.payment_count AS payment_count,
  sm.off_home_store_payment_share AS off_home_store_payment_share,
  sm.max_payment AS max_single_payment,
  cmr.month_payment_rank_within_customer AS month_payment_rank_within_client,
  tcl.categories_for_main_spend AS categories
FROM suspicious_months sm
JOIN customer_month_rank cmr
  ON cmr.customer_id = sm.customer_id
 AND cmr.month_start = sm.month_start
JOIN (
  SELECT customer_id, MAX(customer_name) AS customer_name
  FROM payment_base
  GROUP BY customer_id
) cb
  ON cb.customer_id = sm.customer_id
LEFT JOIN monthly_staff_count msc
  ON msc.customer_id = sm.customer_id
 AND msc.month_start = sm.month_start
LEFT JOIN top_category_list tcl
  ON tcl.customer_id = sm.customer_id
 AND tcl.month_start = sm.month_start
WHERE msc.distinct_payment_stores_count >= 2
ORDER BY sm.month_start, sm.customer_id;