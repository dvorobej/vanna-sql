WITH daily_customer AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT COALESCE(s.j01, p.p04)) AS store_count
  FROM pay AS p
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN inv AS i
    ON i.n01 = r.q03
  LEFT JOIN sto AS s
    ON s.j01 = i.n03
  GROUP BY
    p.p02,
    date(p.p06)
),
with_customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    co.c02 AS country_name,
    ci.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
),
daily_with_history AS (
  SELECT
    dc.*,
    (
      SELECT AVG(CAST(dch.day_amount AS REAL))
      FROM daily_customer AS dch
      WHERE dch.customer_id = dc.customer_id
        AND dch.payment_date >= date(dc.payment_date, '-30 day')
        AND dch.payment_date < dc.payment_date
    ) AS avg_daily_prev_30
  FROM daily_customer AS dc
),
suspicious_days AS (
  SELECT
    dwh.customer_id,
    dwh.payment_date,
    dwh.payment_count,
    dwh.day_amount,
    dwh.avg_daily_prev_30,
    (dwh.day_amount / NULLIF(dwh.avg_daily_prev_30, 0)) AS exceed_ratio,
    RANK() OVER (
      PARTITION BY dwh.customer_id
      ORDER BY dwh.day_amount DESC
    ) AS day_rank_in_customer
  FROM daily_with_history AS dwh
  WHERE dwh.avg_daily_prev_30 IS NOT NULL
    AND dwh.avg_daily_prev_30 > 0
    AND dwh.payment_count >= 3
    AND dwh.day_amount >= 3 * dwh.avg_daily_prev_30
    AND (dwh.staff_count >= 2 OR dwh.store_count >= 2)
)
SELECT
  sd.customer_id,
  cg.country_name,
  cg.city_name,
  sd.payment_date,
  sd.payment_count,
  ROUND(sd.day_amount, 2) AS day_total_amount,
  ROUND(sd.avg_daily_prev_30, 2) AS avg_daily_prev_30_amount,
  ROUND(sd.exceed_ratio, 4) AS exceed_coefficient,
  sd.day_rank_in_customer AS day_rank_by_amount
FROM suspicious_days AS sd
JOIN with_customer_geo AS cg
  ON cg.customer_id = sd.customer_id
ORDER BY
  cg.country_name,
  cg.city_name,
  sd.customer_id,
  sd.payment_date;