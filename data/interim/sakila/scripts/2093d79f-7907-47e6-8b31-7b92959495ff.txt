WITH daily_payments AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS daily_sum,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT COALESCE(inv.n03, stf.o07)) AS store_count
  FROM pay AS p
  JOIN stf AS stf
    ON stf.o01 = p.p03
  LEFT JOIN ren AS ren
    ON ren.q01 = p.p04
  LEFT JOIN inv AS inv
    ON inv.n01 = ren.q03
  GROUP BY
    p.p02,
    date(p.p06)
),
daily_with_baseline AS (
  SELECT
    d.customer_id,
    d.payment_date,
    d.payment_count,
    d.daily_sum,
    d.staff_count,
    d.store_count,
    (
      SELECT COALESCE(SUM(d2.daily_sum), 0) / 30.0
      FROM daily_payments AS d2
      WHERE d2.customer_id = d.customer_id
        AND d2.payment_date >= date(d.payment_date, '-30 days')
        AND d2.payment_date < d.payment_date
    ) AS prev30_avg_daily_sum
  FROM daily_payments AS d
),
suspicious_days AS (
  SELECT
    customer_id,
    payment_date,
    payment_count,
    daily_sum,
    prev30_avg_daily_sum,
    daily_sum - prev30_avg_daily_sum AS deviation_from_average
  FROM daily_with_baseline
  WHERE payment_count >= 3
    AND prev30_avg_daily_sum > 0
    AND daily_sum >= prev30_avg_daily_sum * 3
    AND (staff_count > 1 OR store_count > 1)
)
SELECT
  cus.h01 AS customer_id,
  cus.h03 AS customer_first_name,
  cus.h04 AS customer_last_name,
  cnt.c02 AS country,
  cty.d02 AS city,
  suspicious_days.payment_date,
  suspicious_days.payment_count,
  ROUND(suspicious_days.daily_sum, 2) AS daily_sum,
  ROUND(suspicious_days.prev30_avg_daily_sum, 2) AS prev30_avg_daily_sum,
  ROUND(suspicious_days.deviation_from_average, 2) AS deviation_from_average,
  RANK() OVER (
    ORDER BY suspicious_days.deviation_from_average DESC
  ) AS risk_rank
FROM suspicious_days
JOIN cus AS cus
  ON cus.h01 = suspicious_days.customer_id
JOIN adr AS adr
  ON adr.e01 = cus.h06
JOIN cty AS cty
  ON cty.d01 = adr.e05
JOIN cnt AS cnt
  ON cnt.c01 = cty.d03
ORDER BY
  risk_rank,
  suspicious_days.payment_date,
  cus.h01;