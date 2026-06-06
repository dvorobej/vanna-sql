WITH daily_payments AS (
  SELECT
    p.p02 AS customer_id,
    DATE(p.p06) AS payment_date,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS daily_amount,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay AS p
  JOIN stf AS s
    ON s.o01 = p.p03
  GROUP BY
    p.p02,
    DATE(p.p06)
),
daily_with_avg AS (
  SELECT
    dp.*,
    (
      SELECT AVG(prev.daily_amount)
      FROM daily_payments AS prev
      WHERE prev.customer_id = dp.customer_id
        AND prev.payment_date >= DATE(dp.payment_date, '-30 day')
        AND prev.payment_date < dp.payment_date
    ) AS avg_daily_amount_30d
  FROM daily_payments AS dp
),
suspicious_days AS (
  SELECT
    dwa.customer_id,
    dwa.payment_date,
    dwa.payment_count,
    dwa.daily_amount,
    dwa.avg_daily_amount_30d,
    dwa.daily_amount - dwa.avg_daily_amount_30d AS deviation_amount,
    dwa.daily_amount / NULLIF(dwa.avg_daily_amount_30d, 0) AS deviation_ratio,
    dwa.staff_count,
    dwa.store_count
  FROM daily_with_avg AS dwa
  WHERE dwa.payment_count >= 3
    AND dwa.avg_daily_amount_30d > 0
    AND dwa.daily_amount >= dwa.avg_daily_amount_30d * 3
    AND (
      dwa.staff_count > 1
      OR dwa.store_count > 1
    )
)
SELECT
  cnt.c02 AS country,
  cty.d02 AS city,
  c.h01 AS customer_id,
  c.h03 || ' ' || c.h04 AS customer_name,
  sd.payment_date,
  sd.payment_count,
  ROUND(sd.daily_amount, 2) AS daily_amount,
  ROUND(sd.avg_daily_amount_30d, 2) AS avg_daily_amount_30d,
  ROUND(sd.deviation_amount, 2) AS deviation_amount,
  ROUND(sd.deviation_ratio, 2) AS deviation_ratio,
  sd.staff_count,
  sd.store_count,
  RANK() OVER (
    ORDER BY sd.deviation_ratio DESC, sd.deviation_amount DESC
  ) AS risk_rank
FROM suspicious_days AS sd
JOIN cus AS c
  ON c.h01 = sd.customer_id
JOIN adr AS a
  ON a.e01 = c.h06
JOIN cty
  ON cty.d01 = a.e05
JOIN cnt
  ON cnt.c01 = cty.d03
ORDER BY
  risk_rank,
  sd.daily_amount DESC,
  sd.payment_date,
  c.h01;