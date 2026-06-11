WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cnt.c02 AS country,
    cty.d02 AS city
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS cty ON cty.d01 = a.e05
  JOIN cnt AS cnt ON cnt.c01 = cty.d03
),
daily_customer_payments AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_payment_sum,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count,
    MAX(CAST(p.p05 AS REAL)) AS max_payment_amount
  FROM pay AS p
  JOIN stf AS s ON s.o01 = p.p03
  WHERE p.p06 IS NOT NULL
  GROUP BY p.p02, date(p.p06)
),
daily_customer_with_prev AS (
  SELECT
    d.*,
    (
      SELECT AVG(CAST(prev.day_payment_sum AS REAL))
      FROM daily_customer_payments AS prev
      WHERE prev.customer_id = d.customer_id
        AND prev.payment_date >= date(d.payment_date, '-30 days')
        AND prev.payment_date < d.payment_date
    ) AS avg_prev_30_day_amount
  FROM daily_customer_payments AS d
),
daily_customer_with_rclass_share AS (
  SELECT
    dcp.customer_id,
    dcp.payment_date,
    SUM(
      CASE
        WHEN f.i11 IN ('R','NC-17') THEN CAST(p.p05 AS REAL)
        ELSE 0.0
      END
    ) AS amount_r_or_nc17,
    dcp.day_payment_sum AS day_payment_sum
  FROM daily_customer_with_prev AS dcp
  JOIN pay AS p
    ON p.p02 = dcp.customer_id
   AND date(p.p06) = dcp.payment_date
  JOIN ren AS r ON r.q01 = p.p04
  JOIN inv AS i ON i.n01 = r.q03
  JOIN flm AS f ON f.i01 = i.n02
  GROUP BY dcp.customer_id, dcp.payment_date, dcp.day_payment_sum
),
daily_suspicious AS (
  SELECT
    dcp.customer_id,
    dcp.payment_date,
    dcp.payment_count,
    dcp.day_payment_sum,
    dcp.staff_count,
    dcp.store_count,
    dcp.max_payment_amount,
    dcp.avg_prev_30_day_amount,
    rc.amount_r_or_nc17,
    CASE
      WHEN dcp.day_payment_sum > 0 THEN rc.amount_r_or_nc17 / dcp.day_payment_sum
      ELSE 0.0
    END AS r_or_nc17_share,
    (dcp.day_payment_sum - 3.0 * dcp.avg_prev_30_day_amount) AS excess_over_threshold
  FROM daily_customer_with_prev AS dcp
  JOIN daily_customer_with_rclass_share AS rc
    ON rc.customer_id = dcp.customer_id
   AND rc.payment_date = dcp.payment_date
  WHERE dcp.avg_prev_30_day_amount IS NOT NULL
    AND dcp.avg_prev_30_day_amount > 0
    AND dcp.day_payment_sum >= 3.0 * dcp.avg_prev_30_day_amount
    AND dcp.payment_count >= 3
    AND (dcp.staff_count >= 3 OR dcp.store_count >= 3)
)
SELECT
  cg.city,
  cg.country,
  ds.payment_date AS suspicious_date,
  ds.payment_count,
  ROUND(ds.day_payment_sum, 2) AS day_payment_sum,
  ROUND(ds.max_payment_amount, 2) AS max_payment_amount,
  ROUND(ds.r_or_nc17_share, 4) AS r_or_nc17_share,
  RANK() OVER (
    PARTITION BY cg.country
    ORDER BY ds.excess_over_threshold DESC
  ) AS day_rank_in_country
FROM daily_suspicious AS ds
JOIN customer_geo AS cg
  ON cg.customer_id = ds.customer_id
ORDER BY
  cg.country,
  day_rank_in_country,
  ds.payment_date,
  ds.customer_id;