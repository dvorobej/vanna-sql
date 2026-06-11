WITH payment_enriched AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    c.h06 AS customer_address_id,
    p.p06 AS payment_datetime,
    date(p.p06, 'start of month') AS month_start,
    CAST(p.p05 AS REAL) AS amount,
    p.p03 AS staff_id,
    s.o07 AS staff_store_id,
    r.q01 AS rental_id,
    CASE
      WHEN r.q01 IS NULL THEN 0
      WHEN r.q05 IS NULL THEN 0
      WHEN julianday(r.q05) - julianday(r.q02) > flm.i07 THEN 1
      ELSE 0
    END AS is_late_return_by_rental_duration,
    caddr.e01 AS adr_id,
    ci.d02 AS city_name,
    cn.c02 AS country_name,
    ccn.c01 AS country_id,
    ccn.c02 AS country,
    cst.j01 AS customer_store_id
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN inv AS inv
    ON inv.n01 = r.q03
  LEFT JOIN flm AS flm
    ON flm.i01 = inv.n02
  JOIN stf AS s
    ON s.o01 = p.p03
  JOIN adr AS caddr
    ON caddr.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = caddr.e05
  JOIN cnt AS cn
    ON cn.c01 = ci.d03
  JOIN sto AS cst
    ON cst.j01 = c.h02
  JOIN cnt AS ccn
    ON ccn.c01 = ci.d03
),
monthly_customer AS (
  SELECT
    customer_id,
    first_name,
    last_name,
    customer_address_id,
    month_start,
    city_name,
    country AS country_name,
    staff_store_id AS store_id,
    COUNT(payment_id) AS payment_count,
    SUM(amount) AS payment_sum,
    COUNT(DISTINCT staff_id) AS distinct_staff_count,
    SUM(is_late_return_by_rental_duration) * 1.0 / COUNT(payment_id) AS late_return_payment_share
  FROM payment_enriched
  GROUP BY
    customer_id,
    first_name,
    last_name,
    customer_address_id,
    month_start,
    city_name,
    country,
    staff_store_id
),
monthly_with_prev_avg AS (
  SELECT
    mc.*,
    AVG(mc.payment_sum) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_customer_avg_payment_sum
  FROM monthly_customer AS mc
),
country_store_month_stats AS (
  SELECT
    store_id,
    country_name,
    month_start,
    payment_sum,
    payment_count,
    customer_id,
    first_name,
    last_name,
    customer_address_id,
    city_name,
    distinct_staff_count,
    late_return_payment_share,
    ROW_NUMBER() OVER (
      PARTITION BY store_id, country_name, month_start
      ORDER BY payment_sum
    ) AS rn_asc,
    COUNT(*) OVER (
      PARTITION BY store_id, country_name, month_start
    ) AS cnt_customers
  FROM monthly_with_prev_avg
),
p95_bounds AS (
  SELECT
    store_id,
    country_name,
    month_start,
    CAST((cnt_customers + 1) * 0.95 AS INTEGER) AS p95_pos_low,
    CAST((cnt_customers + 1) * 0.95 AS INTEGER) + 1 AS p95_pos_high,
    MAX(CASE WHEN p95_pos_low < 1 THEN 1 ELSE p95_pos_low END) AS p95_pos_low_adj,
    MAX(CASE WHEN p95_pos_high < 1 THEN 1 ELSE p95_pos_high END) AS p95_pos_high_adj
  FROM (
    SELECT DISTINCT
      store_id, country_name, month_start, cnt_customers
    FROM country_store_month_stats
  ) t
  CROSS JOIN (
    SELECT 0
  ) dummy
  GROUP BY store_id, country_name, month_start, cnt_customers
),
p95_values AS (
  SELECT
    s.store_id,
    s.country_name,
    s.month_start,
    MAX(CASE WHEN s.rn_asc = pb.p95_pos_low_adj THEN s.payment_sum END) AS p95_payment_sum_low,
    MAX(CASE WHEN s.rn_asc = pb.p95_pos_high_adj THEN s.payment_sum END) AS p95_payment_sum_high
  FROM country_store_month_stats AS s
  JOIN p95_bounds AS pb
    ON pb.store_id = s.store_id
   AND pb.country_name = s.country_name
   AND pb.month_start = s.month_start
  GROUP BY s.store_id, s.country_name, s.month_start
),
thresholded AS (
  SELECT
    s.*,
    pv.p95_payment_sum_low,
    pv.p95_payment_sum_high,
    CASE
      WHEN pv.p95_payment_sum_high IS NULL THEN pv.p95_payment_sum_low
      ELSE pv.p95_payment_sum_high
    END AS p95_payment_sum
  FROM country_store_month_stats AS s
  JOIN p95_values AS pv
    ON pv.store_id = s.store_id
   AND pv.country_name = s.country_name
   AND pv.month_start = s.month_start
),
ranked_in_store AS (
  SELECT
    t.*,
    RANK() OVER (
      PARTITION BY t.store_id, t.country_name, t.month_start
      ORDER BY t.payment_sum DESC
    ) AS customer_store_month_rank
  FROM thresholded AS t
)
SELECT
  r.first_name || ' ' || r.last_name AS customer_name,
  r.customer_id,
  r.customer_address_id,
  r.city_name,
  r.country_name,
  r.store_id,
  strftime('%Y-%m', r.month_start) AS payment_month,
  ROUND(r.payment_sum, 2) AS payment_sum,
  r.payment_count,
  r.distinct_staff_count AS distinct_staff_count,
  ROUND(r.late_return_payment_share, 4) AS late_return_payment_share,
  r.customer_store_month_rank
FROM ranked_in_store AS r
WHERE r.prev_customer_avg_payment_sum IS NOT NULL
  AND r.payment_sum >= 3 * r.prev_customer_avg_payment_sum
  AND r.payment_sum > r.p95_payment_sum
ORDER BY
  r.country_name,
  r.store_id,
  r.month_start,
  r.payment_sum DESC,
  r.customer_id;