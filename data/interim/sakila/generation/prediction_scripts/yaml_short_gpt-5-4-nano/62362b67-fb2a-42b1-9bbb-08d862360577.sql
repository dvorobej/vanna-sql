WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country_name,
    cty.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty
    ON cty.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = cty.d03
),
daily AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay AS p
  JOIN stf AS s
    ON s.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06)
),
daily_with_avg AS (
  SELECT
    d.*,
    (
      SELECT AVG(d2.day_amount)
      FROM daily AS d2
      WHERE d2.customer_id = d.customer_id
        AND d2.payment_date >= date(d.payment_date, '-30 days')
        AND d2.payment_date < d.payment_date
    ) AS avg_prev_30d
  FROM daily AS d
),
suspicious AS (
  SELECT
    dwa.*,
    CASE
      WHEN dwa.avg_prev_30d > 0 THEN dwa.day_amount / dwa.avg_prev_30d
      ELSE NULL
    END AS exceed_ratio
  FROM daily_with_avg AS dwa
  WHERE dwa.avg_prev_30d IS NOT NULL
    AND dwa.avg_prev_30d > 0
    AND dwa.day_amount >= 3.0 * dwa.avg_prev_30d
)
SELECT
  s.customer_id,
  cg.customer_name,
  cg.country_name,
  cg.city_name,
  s.payment_date,
  ROUND(s.day_amount, 2) AS day_amount,
  s.payment_count,
  s.staff_count,
  s.store_count,
  RANK() OVER (
    ORDER BY s.exceed_ratio DESC, s.day_amount DESC, s.payment_date
  ) AS suspicion_rank
FROM suspicious AS s
JOIN customer_geo AS cg
  ON cg.customer_id = s.customer_id
ORDER BY
  suspicion_rank,
  s.day_amount DESC,
  s.payment_date;