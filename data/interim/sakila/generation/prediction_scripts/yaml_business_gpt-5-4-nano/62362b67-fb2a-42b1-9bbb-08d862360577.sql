WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS customer_country,
    city.d02 AS customer_city
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS city
    ON city.d01 = a.e05
  JOIN sto AS dummy
    ON dummy.j01 = c.h02
  JOIN cnt AS cnt
    ON cnt.c01 = city.d03
),
daily_payments AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_day,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS daily_amount,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay AS p
  JOIN stf AS s
    ON s.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06)
),
with_history AS (
  SELECT
    dp.*,
    (
      SELECT AVG(dph.daily_amount)
      FROM daily_payments AS dph
      WHERE dph.customer_id = dp.customer_id
        AND dph.payment_day >= date(dp.payment_day, '-30 days')
        AND dph.payment_day < dp.payment_day
    ) AS avg_daily_amount_prev_30d
  FROM daily_payments AS dp
),
suspicious_days AS (
  SELECT
    wh.*,
    (wh.daily_amount / NULLIF(wh.avg_daily_amount_prev_30d, 0)) AS exceed_ratio
  FROM with_history AS wh
  WHERE wh.avg_daily_amount_prev_30d IS NOT NULL
    AND wh.avg_daily_amount_prev_30d > 0
    AND wh.daily_amount >= 3.0 * wh.avg_daily_amount_prev_30d
    AND (wh.staff_count >= 2 OR wh.store_count >= 2)
),
ranked AS (
  SELECT
    sd.*,
    RANK() OVER (
      PARTITION BY sd.customer_id
      ORDER BY (sd.daily_amount - sd.avg_daily_amount_prev_30d) DESC
    ) AS suspicion_rank_within_customer
  FROM suspicious_days AS sd
)
SELECT
  r.customer_id,
  cg.customer_name,
  cg.customer_city,
  cg.customer_country,
  r.payment_day AS anomaly_date,
  r.payment_count,
  ROUND(r.daily_amount, 2) AS daily_amount,
  r.staff_count AS involved_staff_count,
  ROUND(r.avg_daily_amount_prev_30d, 2) AS avg_daily_amount_prev_30d,
  r.exceed_ratio,
  r.suspicion_rank_within_customer
FROM ranked AS r
JOIN customer_geo AS cg
  ON cg.customer_id = r.customer_id
ORDER BY
  cg.customer_country,
  cg.customer_city,
  r.customer_id,
  r.suspicion_rank_within_customer,
  r.daily_amount DESC;