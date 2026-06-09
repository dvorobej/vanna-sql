SELECT min_month
  FROM month_bounds
  UNION ALL
  SELECT date(month_start, '+1 month')
  FROM months, month_bounds
  WHERE month_start < max_month
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS customer_first_name,
    c.h04 AS customer_last_name,
    cnt.c02 AS country_name,
    ci.d02 AS city_name,
    c.h02 AS customer_home_store_id
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt ON cnt.c01 = ci.d03
),
pay_base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p03 AS staff_id,
    r.q01 AS rental_id,
    i.n03 AS issuing_store_id
  FROM pay AS p
  JOIN ren AS r ON r.q01 = p.p04
  JOIN inv AS i ON i.n01 = r.q03
),
monthly_customer AS (
  SELECT
    pb.customer_id,
    cg.customer_first_name,
    cg.customer_last_name,
    cg.country_name,
    cg.city_name,
    pb.issuing_store_id,
    pb.month_start,
    COUNT(*) AS payment_count,
    SUM(pb.payment_amount) AS payment_sum,
    COUNT(DISTINCT pb.staff_id) AS distinct_staff_count,
    SUM(CASE
          WHEN r.q05 IS NOT NULL
           AND julianday(r.q05) - julianday(r.q02) > flm.i07
          THEN 1
          ELSE 0
        END
    ) * 1.0 / COUNT(*) AS late_return_share
  FROM pay_base AS pb
  JOIN customer_geo AS cg ON cg.customer_id = pb.customer_id
  JOIN ren AS r ON r.q01 = pb.rental_id
  JOIN inv AS i ON i.n01 = r.q03
  JOIN flm ON flm.i01 = i.n02
  GROUP BY
    pb.customer_id,
    cg.customer_first_name,
    cg.customer_last_name,
    cg.country_name,
    cg.city_name,
    pb.issuing_store_id,
    pb.month_start
),
monthly_with_prev AS (
  SELECT
    mc.*,
    AVG(mc.payment_sum) OVER (
      PARTITION BY mc.customer_id, mc.issuing_store_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_avg_prev_months_sum
  FROM monthly_customer AS mc
),
country_store_p95 AS (
  SELECT
    m1.issuing_store_id,
    m1.country_name,
    m1.month_start,
    m1.payment_sum,
    PERCENT_RANK() OVER (
      PARTITION BY m1.issuing_store_id, m1.country_name, m1.month_start
      ORDER BY m1.payment_sum
    ) AS pr
  FROM monthly_with_prev AS m1
),
country_store_p95_cut AS (
  SELECT
    issuing_store_id,
    country_name,
    month_start,
    MAX(payment_sum) AS p95_payment_sum
  FROM country_store_p95
  WHERE pr >= 0.95
  GROUP BY
    issuing_store_id, country_name, month_start
),
rank_in_store AS (
  SELECT
    mwp.*,
    RANK() OVER (
      PARTITION BY mwp.issuing_store_id, mwp.month_start
      ORDER BY mwp.payment_sum DESC
    ) AS store_month_customer_rank
  FROM monthly_with_prev AS mwp
)
SELECT
  ris.customer_id,
  ris.customer_first_name || ' ' || ris.customer_last_name AS customer_name,
  ris.country_name,
  ris.city_name,
  ris.issuing_store_id AS store_id,
  strftime('%Y-%m', ris.month_start) AS payment_month,
  ROUND(ris.payment_sum, 2) AS month_payment_sum,
  ris.payment_count,
  ris.distinct_staff_count AS distinct_staff_count,
  ROUND(ris.late_return_share, 4) AS late_return_share,
  ris.store_month_customer_rank AS store_month_customer_rank
FROM rank_in_store AS ris
JOIN country_store_p95_cut AS cut
  ON cut.issuing_store_id = ris.issuing_store_id
 AND cut.country_name = ris.country_name
 AND cut.month_start = ris.month_start
WHERE ris.personal_avg_prev_months_sum IS NOT NULL
  AND ris.personal_avg_prev_months_sum > 0
  AND ris.payment_sum >= 3.0 * ris.personal_avg_prev_months_sum
  AND ris.payment_sum > cut.p95_payment_sum
ORDER BY
  ris.month_start,
  ris.store_month_customer_rank,
  ris.customer_id;