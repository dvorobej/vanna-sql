WITH daily_payments AS (
  SELECT
    c.h01 AS customer_id,
    date(p.p06) AS day_date,
    COUNT(p.p01) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_sum,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT s.o07) AS distinct_store_count
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
  LEFT JOIN stf AS s
    ON s.o01 = p.p03
  GROUP BY
    c.h01,
    date(p.p06)
),
daily_with_prev_avg AS (
  SELECT
    dp.*,
    (
      SELECT AVG(CAST(d2.day_sum AS REAL))
      FROM daily_payments AS d2
      WHERE d2.customer_id = dp.customer_id
        AND d2.day_date >= date(dp.day_date, '-30 days')
        AND d2.day_date < dp.day_date
    ) AS avg_prev_30_days
  FROM daily_payments AS dp
),
flagged_days AS (
  SELECT
    dwp.*,
    (dwp.day_sum / dwp.avg_prev_30_days) AS exceed_ratio,
    ROW_NUMBER() OVER (
      PARTITION BY dwp.customer_id
      ORDER BY dwp.day_sum DESC, dwp.day_date DESC
    ) AS day_rank
  FROM daily_with_prev_avg AS dwp
  WHERE dwp.payment_count >= 3
    AND dwp.avg_prev_30_days IS NOT NULL
    AND dwp.avg_prev_30_days > 0
    AND dwp.day_sum >= 3 * dwp.avg_prev_30_days
    AND (dwp.distinct_staff_count >= 2 OR dwp.distinct_store_count >= 2)
)
SELECT
  customer_id AS h01,
  day_date AS suspicious_date,
  payment_count,
  ROUND(day_sum, 2) AS day_sum,
  ROUND(avg_prev_30_days, 2) AS avg_prev_30_days,
  ROUND(day_sum / avg_prev_30_days, 4) AS exceed_ratio,
  day_rank AS customer_day_rank
FROM flagged_days
ORDER BY customer_day_rank, h01, suspicious_date;