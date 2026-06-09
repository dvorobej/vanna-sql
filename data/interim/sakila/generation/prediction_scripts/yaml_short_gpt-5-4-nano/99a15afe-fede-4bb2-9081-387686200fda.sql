WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    a.e05 AS city_id,
    ci.d02 AS city_name,
    co.c01 AS country_id,
    co.c02 AS country_name,
    c.h02 AS home_store_id
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ci.d03
),
payment_base AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS monthly_pay_amount,
    COUNT(DISTINCT p.p03) AS staff_count_in_month,
    SUM(
      CASE
        WHEN r.q05 IS NOT NULL AND r.q05 > date(r.q02, '+' || f.i07 || ' days')
          THEN 1
        ELSE 0
      END
    ) * 1.0 / COUNT(*) AS overdue_return_share,
    COALESCE(cg.country_id, 0) AS country_id,
    COALESCE(cg.city_id, 0) AS city_id,
    COALESCE(cg.home_store_id, 0) AS home_store_id
  FROM pay AS p
  JOIN ren AS r ON r.q01 = p.p04
  JOIN inv AS i ON i.n01 = r.q03
  JOIN flm AS f ON f.i01 = i.n01
  LEFT JOIN customer_geo AS cg ON cg.customer_id = p.p02
  GROUP BY
    p.p02,
    date(p.p06, 'start of month'),
    cg.country_id,
    cg.city_id,
    cg.home_store_id
),
history_scored AS (
  SELECT
    pb.*,
    AVG(pb.monthly_pay_amount) OVER (
      PARTITION BY pb.customer_id
      ORDER BY pb.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS avg_prev_months_amount
  FROM payment_base AS pb
),
store_country_top_p95 AS (
  SELECT
    hs.country_id,
    hs.home_store_id,
    hs.month_start,
    hs.monthly_pay_amount,
    PERCENT_RANK() OVER (
      PARTITION BY hs.country_id, hs.home_store_id, hs.month_start
      ORDER BY hs.monthly_pay_amount DESC
    ) AS store_country_month_percent_rank
  FROM history_scored AS hs
)
SELECT
  cc.country_name,
  ct.city_name,
  hs.home_store_id AS store_id,
  strftime('%Y-%m', hs.month_start) AS payment_month,
  ROUND(hs.monthly_pay_amount, 2) AS monthly_pay_amount,
  hs.payment_count,
  hs.staff_count_in_month AS staff_count,
  ROUND(hs.overdue_return_share, 4) AS overdue_return_share,
  DENSE_RANK() OVER (
    PARTITION BY hs.country_id, hs.month_start
    ORDER BY hs.monthly_pay_amount DESC
  ) AS sum_payment_rank_in_country
FROM history_scored AS hs
JOIN cnt AS cc ON cc.c01 = hs.country_id
JOIN cty AS ct ON ct.d01 = hs.city_id
JOIN store_country_top_p95 AS sp
  ON sp.country_id = hs.country_id
 AND sp.home_store_id = hs.home_store_id
 AND sp.month_start = hs.month_start
 AND sp.monthly_pay_amount = hs.monthly_pay_amount
WHERE hs.avg_prev_months_amount IS NOT NULL
  AND hs.avg_prev_months_amount > 0
  AND hs.monthly_pay_amount >= 3 * hs.avg_prev_months_amount
  AND sp.store_country_month_percent_rank <= 0.05
ORDER BY
  hs.month_start,
  cc.country_name,
  hs.monthly_pay_amount DESC,
  hs.home_store_id;