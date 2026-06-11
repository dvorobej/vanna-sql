WITH
payments_agg AS (
  SELECT
    co.c01 AS country_id,
    co.c02 AS country_name,
    ct.d01 AS city_id,
    ct.d02 AS city_name,
    c.h02 AS store_id,
    strftime('%Y-%m', p.p06) AS payment_month,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS payment_sum,
    MAX(CAST(p.p05 AS REAL)) AS payment_max,

    SUM(CASE WHEN fc.g02 = 'Action' THEN CAST(p.p05 AS REAL) ELSE 0 END) AS action_amount,
    SUM(CASE WHEN fc.g02 = 'New' THEN CAST(p.p05 AS REAL) ELSE 0 END) AS new_amount
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ct.d03
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS i
    ON i.n01 = r.q03
  JOIN flc AS flc
    ON flc.l01 = i.n02
  JOIN cat AS fc
    ON fc.g01 = flc.l02
  GROUP BY
    co.c01, co.c02,
    ct.d01, ct.d02,
    c.h02,
    strftime('%Y-%m', p.p06)
),
with_shares AS (
  SELECT
    pa.*,
    ROUND(pa.action_amount / NULLIF(pa.payment_sum, 0), 4) AS action_share,
    ROUND(pa.new_amount / NULLIF(pa.payment_sum, 0), 4) AS new_share
  FROM payments_agg pa
),
ranked AS (
  SELECT
    ws.*,
    RANK() OVER (
      PARTITION BY ws.country_id, ws.payment_month
      ORDER BY ws.payment_sum DESC
    ) AS country_month_rank
  FROM with_shares ws
)
SELECT
  payment_month AS month,
  country_name,
  city_name,
  store_id,
  ROUND(payment_sum, 2) AS payment_sum,
  payment_count,
  ROUND(payment_max, 2) AS payment_max,
  ROUND(action_amount, 2) AS action_amount,
  ROUND(new_amount, 2) AS new_amount,
  action_share,
  new_share,
  country_month_rank
FROM ranked
ORDER BY
  payment_month,
  country_month_rank,
  payment_sum DESC;