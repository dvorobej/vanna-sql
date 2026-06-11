WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    co.c02 AS country_name,
    ci.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ci.d03
),
daily_customer AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_total_amount,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT s.o07) AS distinct_store_count
  FROM pay AS p
  JOIN stf AS s ON s.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06)
),
daily_scored AS (
  SELECT
    dc.customer_id,
    dc.payment_date,
    dc.payment_count,
    dc.day_total_amount,
    dc.distinct_staff_count,
    dc.distinct_store_count,
    (
      SELECT AVG(CAST(dcp.day_total_amount AS REAL))
      FROM daily_customer AS dcp
      WHERE dcp.customer_id = dc.customer_id
        AND dcp.payment_date >= date(dc.payment_date, '-30 days')
        AND dcp.payment_date < dc.payment_date
    ) AS avg_prev_30d_amount
  FROM daily_customer AS dc
),
suspicious_days AS (
  SELECT
    ds.*,
    ds.day_total_amount / NULLIF(ds.avg_prev_30d_amount, 0) AS excess_ratio
  FROM daily_scored AS ds
  WHERE ds.avg_prev_30d_amount IS NOT NULL
    AND ds.avg_prev_30d_amount > 0
    AND ds.payment_count >= 3
    AND (ds.distinct_staff_count >= 2 OR ds.distinct_store_count >= 2)
    AND ds.day_total_amount >= 3 * ds.avg_prev_30d_amount
),
ranked AS (
  SELECT
    sd.*,
    RANK() OVER (
      PARTITION BY sd.customer_id
      ORDER BY sd.day_total_amount DESC
    ) AS day_amount_rank_in_customer
  FROM suspicious_days AS sd
)
SELECT
  r.customer_id,
  cg.customer_name,
  cg.country_name,
  cg.city_name,
  r.payment_date AS suspicious_date,
  r.payment_count,
  ROUND(r.day_total_amount, 2) AS day_total_amount,
  ROUND(r.avg_prev_30d_amount, 2) AS avg_daily_prev_30d_amount,
  ROUND(r.excess_ratio, 4) AS excess_ratio,
  r.day_amount_rank_in_customer
FROM ranked AS r
JOIN customer_geo AS cg
  ON cg.customer_id = r.customer_id
ORDER BY
  cg.country_name,
  cg.city_name,
  r.customer_id,
  r.day_amount_rank_in_customer,
  r.payment_date;