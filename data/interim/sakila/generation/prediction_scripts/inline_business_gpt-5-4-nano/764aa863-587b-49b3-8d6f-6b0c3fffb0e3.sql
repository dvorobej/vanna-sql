WITH payment_base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    CAST(p.p05 AS REAL) AS amount,
    p.p03 AS staff_id,
    r.q01 AS rental_id,
    i.n03 AS issuing_store_id,
    flc.l02 AS category_id,
    CASE
      WHEN sf.o07 <> c.h02 THEN 1
      ELSE 0
    END AS is_off_home_store_payment
  FROM pay AS p
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS i
    ON i.n01 = r.q03
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN stf AS sf
    ON sf.o01 = p.p03
  JOIN flc
    ON flc.l01 = i.n02
),
customer_month_rollup AS (
  SELECT
    pb.customer_id,
    pb.month_start,
    c.h03 || ' ' || c.h04 AS customer_name,
    co.c02 AS country_name,
    ci.d02 AS city_name,
    COUNT(*) AS payment_count,
    SUM(pb.amount) AS month_total_amount,
    MAX(pb.amount) AS max_payment_amount,
    AVG(pb.amount) AS avg_payment_amount,
    COUNT(DISTINCT pb.staff_id) AS distinct_staff_count,
    SUM(pb.is_off_home_store_payment) AS off_home_store_payment_count,
    1.0 * SUM(pb.is_off_home_store_payment) / NULLIF(COUNT(*), 0) AS off_home_store_payment_share,
    COUNT(DISTINCT pb.category_id) AS distinct_category_count
  FROM payment_base AS pb
  JOIN cus AS c
    ON c.h01 = pb.customer_id
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
  GROUP BY
    pb.customer_id,
    pb.month_start,
    c.h03,
    c.h04,
    co.c02,
    ci.d02
),
customer_month_with_prev_avg AS (
  SELECT
    cm.*,
    AVG(cm.month_total_amount) OVER (
      PARTITION BY cm.customer_id
      ORDER BY cm.month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS avg_prev_3_months_amount
  FROM customer_month_rollup AS cm
),
ranked_by_country_month AS (
  SELECT
    cm.*,
    RANK() OVER (
      PARTITION BY cm.country_name, cm.month_start
      ORDER BY cm.month_total_amount DESC
    ) AS country_month_amount_rank
  FROM customer_month_with_prev_avg AS cm
)
SELECT
  rb.country_name,
  rb.city_name,
  rb.customer_id,
  rb.customer_name,
  rb.month_start AS payment_month_start,
  ROUND(rb.month_total_amount, 2) AS month_total_amount,
  rb.payment_count,
  ROUND(rb.max_payment_amount, 2) AS max_payment_amount,
  ROUND(rb.off_home_store_payment_share, 4) AS off_home_store_payment_share,
  rb.distinct_staff_count,
  rb.distinct_category_count,
  rb.country_month_amount_rank
FROM ranked_by_country_month AS rb
WHERE rb.avg_prev_3_months_amount IS NOT NULL
  AND rb.avg_prev_3_months_amount > 0
  AND rb.month_total_amount > 3.0 * rb.avg_prev_3_months_amount
  AND rb.distinct_staff_count >= 2
  AND rb.distinct_category_count >= 3
ORDER BY
  rb.month_start,
  rb.country_name,
  rb.country_month_amount_rank,
  rb.month_total_amount DESC;