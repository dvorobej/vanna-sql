WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    cnt.c02 AS customer_country,
    cty.d02 AS customer_city
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS cty ON cty.d01 = a.e05
  JOIN cnt AS cnt ON cnt.c01 = cty.d03
),
daily AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_total_amount,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT st.o07) AS store_count
  FROM pay AS p
  JOIN stf AS st ON st.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06)
),
daily_with_prev AS (
  SELECT
    d.*,
    (
      SELECT AVG(d2.day_total_amount)
      FROM daily AS d2
      WHERE d2.customer_id = d.customer_id
        AND d2.payment_date >= date(d.payment_date, '-30 day')
        AND d2.payment_date < d.payment_date
    ) AS avg_prev_30d_amount
  FROM daily AS d
),
suspicious AS (
  SELECT
    dwp.*,
    (dwp.day_total_amount / NULLIF(dwp.avg_prev_30d_amount, 0.0)) AS exceed_ratio
  FROM daily_with_prev AS dwp
  WHERE dwp.avg_prev_30d_amount IS NOT NULL
    AND dwp.avg_prev_30d_amount > 0
    AND dwp.payment_count >= 3
    AND dwp.day_total_amount >= 3 * dwp.avg_prev_30d_amount
    AND (dwp.staff_count >= 2 OR dwp.store_count >= 2)
),
ranked AS (
  SELECT
    s.*,
    DENSE_RANK() OVER (
      PARTITION BY s.customer_id
      ORDER BY s.day_total_amount DESC
    ) AS day_rank_for_customer
  FROM suspicious AS s
)
SELECT
  r.customer_id,
  cg.customer_country,
  cg.customer_city,
  r.payment_date,
  r.payment_count,
  ROUND(r.day_total_amount, 2) AS day_total_amount,
  ROUND(r.avg_prev_30d_amount, 2) AS avg_prev_30d_amount,
  ROUND(r.exceed_ratio, 4) AS exceed_ratio,
  r.day_rank_for_customer
FROM ranked AS r
JOIN customer_geo AS cg
  ON cg.customer_id = r.customer_id
ORDER BY
  r.customer_id,
  r.day_rank_for_customer,
  r.payment_date;