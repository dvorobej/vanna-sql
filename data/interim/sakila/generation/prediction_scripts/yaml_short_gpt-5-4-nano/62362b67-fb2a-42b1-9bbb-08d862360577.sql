WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country_name,
    cty.d02 AS city_name,
    c.h06 AS address_id
  FROM cus AS c
  JOIN adr ON adr.e01 = c.h06
  JOIN cty ON cty.d01 = adr.e05
  JOIN cnt ON cnt.c01 = cty.d03
),
daily AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay AS p
  JOIN stf AS s ON s.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06)
),
daily_with_prev AS (
  SELECT
    d.*,
    (
      SELECT AVG(d2.day_amount)
      FROM daily AS d2
      WHERE d2.customer_id = d.customer_id
        AND d2.payment_date >= date(d.payment_date, '-30 days')
        AND d2.payment_date < d.payment_date
    ) AS avg_daily_amount_prev_30d
  FROM daily AS d
)
SELECT
  dg.customer_id,
  dg.customer_name,
  dg.country_name,
  dg.city_name,
  dwp.payment_date,
  ROUND(dwp.day_amount, 2) AS day_amount,
  dwp.payment_count,
  dwp.staff_count,
  dwp.store_count,
  RANK() OVER (
    PARTITION BY dg.country_name, dg.city_name
    ORDER BY dwp.day_amount DESC
  ) AS suspicion_rank
FROM daily_with_prev AS dwp
JOIN customer_geo AS dg
  ON dg.customer_id = dwp.customer_id
WHERE dwp.avg_daily_amount_prev_30d IS NOT NULL
  AND dwp.avg_daily_amount_prev_30d > 0
  AND dwp.day_amount >= 3.0 * dwp.avg_daily_amount_prev_30d
ORDER BY
  dg.country_name,
  dg.city_name,
  suspicion_rank,
  dwp.payment_date,
  dg.customer_id;