WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    co.c02 AS country_name,
    ci.d02 AS city_name,
    c.h02 AS home_store_id
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ci.d03
  WHERE c.h07 = 'Y'
),
payment_base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    cg.home_store_id,
    cg.country_name,
    cg.city_name,
    p.p04 AS rental_id,
    p.p05 AS amount,
    p.p06 AS payment_date,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id
  FROM pay AS p
  JOIN customer_geo AS cg
    ON cg.customer_id = p.p02
),
monthly_customer AS (
  SELECT
    pb.customer_id,
    pb.home_store_id,
    pb.country_name,
    pb.city_name,
    pb.month_start,
    COUNT(*) AS payment_count,
    SUM(pb.amount) AS month_amount,
    MAX(pb.amount) AS max_payment,
    COUNT(DISTINCT pb.staff_id) AS distinct_staff_count,
    SUM(
      CASE
        WHEN r.q05 IS NOT NULL
         AND inv_flm.i07 IS NOT NULL
         AND r.q05 > datetime(r.q02, printf('+%d days', inv_flm.i07))
        THEN 1
        ELSE 0
      END
    ) AS late_rental_payment_count
  FROM payment_base AS pb
  LEFT JOIN ren AS r ON r.q01 = pb.rental_id
  LEFT JOIN inv AS inv ON inv.n01 = r.q03
  LEFT JOIN flm AS inv_flm ON inv_flm.i01 = inv.n02
  GROUP BY
    pb.customer_id, pb.home_store_id, pb.country_name, pb.city_name, pb.month_start
),
monthly_with_history AS (
  SELECT
    mc.*,
    AVG(mc.month_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS avg_prev_month_amount
  FROM monthly_customer AS mc
),
store_country_percentiles AS (
  SELECT
    mc.home_store_id,
    mc.country_name,
    mc.month_start,
    (
      SELECT x.month_amount
      FROM monthly_customer AS x
      WHERE x.home_store_id = mc.home_store_id
        AND x.country_name = mc.country_name
        AND x.month_start = mc.month_start
      ORDER BY x.month_amount
      LIMIT 1 OFFSET (
        CAST(0.95 * (COUNT(*) OVER (
          PARTITION BY mc.home_store_id, mc.country_name, mc.month_start
        ) - 1) AS INTEGER)
      )
    ) AS p95_month_amount
  FROM monthly_customer AS mc
  GROUP BY mc.home_store_id, mc.country_name, mc.month_start
),
joined AS (
  SELECT
    mwh.*,
    scp.p95_month_amount,
    CASE
      WHEN mwh.payment_count > 0 THEN 1.0 * mwh.late_rental_payment_count / mwh.payment_count
      ELSE 0
    END AS late_rental_payment_share
  FROM monthly_with_history AS mwh
  JOIN store_country_percentiles AS scp
    ON scp.home_store_id = mwh.home_store_id
   AND scp.country_name = mwh.country_name
   AND scp.month_start = mwh.month_start
),
ranked_in_store AS (
  SELECT
    j.*,
    RANK() OVER (
      PARTITION BY j.home_store_id, j.month_start
      ORDER BY j.month_amount DESC
    ) AS customer_store_month_rank
  FROM joined AS j
)
SELECT
  r.home_store_id AS store_id,
  cg.first_name,
  cg.last_name,
  r.customer_id,
  cg.city_name,
  r.country_name,
  strftime('%Y-%m', r.month_start) AS payment_month,
  ROUND(r.month_amount, 2) AS month_amount,
  r.payment_count,
  r.distinct_staff_count,
  ROUND(r.late_rental_payment_share, 4) AS late_rental_payment_share,
  r.customer_store_month_rank
FROM ranked_in_store AS r
JOIN customer_geo AS cg
  ON cg.customer_id = r.customer_id
WHERE r.avg_prev_month_amount IS NOT NULL
  AND r.avg_prev_month_amount > 0
  AND r.month_amount >= 3.0 * r.avg_prev_month_amount
  AND r.month_amount > r.p95_month_amount
ORDER BY
  r.month_start,
  r.home_store_id,
  r.month_amount DESC,
  r.customer_id;