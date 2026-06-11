WITH payment_monthly AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cnt.c02 AS country_name,
    cty.d02 AS city_name,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS payment_sum,
    MAX(p.p05) AS max_payment,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT COALESCE(r.q03, -1)) AS inventory_count,
    COUNT(DISTINCT COALESCE(inv.n03, -1)) AS store_count,
    SUM(CASE WHEN flm.i11 IN ('R','NC-17') THEN p.p05 ELSE 0 END) AS r_nc17_sum
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS adr_c
    ON adr_c.e01 = c.h06
  JOIN cty AS cty
    ON cty.d01 = adr_c.e05
  JOIN cnt AS cnt
    ON cnt.c01 = cty.d03
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN inv
    ON inv.n01 = r.q03
  LEFT JOIN flm
    ON flm.i01 = inv.n02
  -- ensure store_count uses store from issuing location (if inv has n03 as store_id)
  -- if inv.n03 is not store_id in your schema, replace COALESCE(inv.n03, -1) accordingly
  GROUP BY
    c.h01, c.h03, c.h04, cnt.c02, cty.d02, date(p.p06, 'start of month')
),
with_history AS (
  SELECT
    pm.*,
    AVG(pm.payment_sum) OVER (
      PARTITION BY pm.customer_id
      ORDER BY pm.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS avg_prev_monthly_sum,
    COUNT(*) OVER (
      PARTITION BY pm.customer_id
      ORDER BY pm.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_months_count
  FROM payment_monthly pm
),
month_satisfying AS (
  SELECT
    wh.*
  FROM with_history wh
  WHERE wh.avg_prev_monthly_sum IS NOT NULL
    AND wh.avg_prev_monthly_sum > 0
    AND wh.payment_sum > 3.0 * wh.avg_prev_monthly_sum
    AND wh.payment_count >= 3
    AND EXISTS (
      SELECT 1
      FROM (
        SELECT
          date(p2.p06) AS d,
          COUNT(*) AS cnt
        FROM pay p2
        WHERE p2.p02 = wh.customer_id
          AND date(p2.p06, 'start of month') = wh.month_start
        GROUP BY date(p2.p06)
      ) days
    )
    AND (
      SELECT COUNT(DISTINCT date(p2.p06))
      FROM pay p2
      WHERE p2.p02 = wh.customer_id
        AND date(p2.p06, 'start of month') = wh.month_start
    ) >= 3
),
ranked AS (
  SELECT
    ms.*,
    RANK() OVER (
      PARTITION BY ms.country_name
      ORDER BY ms.payment_sum DESC
    ) AS country_month_rank
  FROM month_satisfying ms
)
SELECT
  month_start AS month,
  customer_id,
  first_name,
  last_name,
  country_name AS country,
  city_name AS city,
  payment_count,
  ROUND(payment_sum, 2) AS payment_sum,
  ROUND(max_payment, 2) AS max_payment,
  ROUND(CASE WHEN payment_sum = 0 THEN 0 ELSE 1.0 * max_payment / payment_sum END, 4) AS max_payment_share,
  staff_count,
  store_count,
  country_month_rank
FROM ranked
ORDER BY
  country,
  month,
  country_month_rank,
  customer_id;