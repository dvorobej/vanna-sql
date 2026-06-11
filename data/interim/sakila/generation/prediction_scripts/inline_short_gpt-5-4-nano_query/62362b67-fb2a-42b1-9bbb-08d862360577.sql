WITH daily AS (
  SELECT
    p.p02 AS customer_id,
    cnt.c02 AS customer_country,
    cty.d02 AS customer_city,
    date(p.p06) AS payment_day,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS day_amount,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay p
  JOIN cus c ON c.h01 = p.p02
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ON cty.d01 = a.e05
  JOIN cnt ON cnt.c01 = cty.d03
  JOIN stf s ON s.o01 = p.p03
  GROUP BY
    p.p02, cnt.c02, cty.d02, date(p.p06)
),
daily_with_history AS (
  SELECT
    d.*,
    (
      SELECT AVG(d2.day_amount)
      FROM daily d2
      WHERE d2.customer_id = d.customer_id
        AND d2.payment_day >= date(d.payment_day, '-30 days')
        AND d2.payment_day < d.payment_day
    ) AS avg_prev_30d
  FROM daily d
),
suspicious AS (
  SELECT
    dw.customer_id,
    dw.customer_country,
    dw.customer_city,
    dw.payment_day AS suspicious_date,
    dw.day_amount,
    dw.payment_count,
    dw.staff_count,
    dw.store_count,
    dw.avg_prev_30d,
    (dw.day_amount - dw.avg_prev_30d) AS excess_over_history
  FROM daily_with_history dw
  WHERE dw.avg_prev_30d IS NOT NULL
    AND dw.avg_prev_30d > 0
    AND dw.day_amount >= 3.0 * dw.avg_prev_30d
    AND (dw.staff_count >= 2 OR dw.store_count >= 2)
)
SELECT
  c.h03 AS first_name,
  c.h04 AS last_name,
  s.customer_country,
  s.customer_city,
  s.suspicious_date,
  s.day_amount AS day_total_amount,
  s.payment_count,
  s.staff_count AS distinct_staff_count,
  ROUND(s.avg_prev_30d, 2) AS avg_daily_amount_prev_30_days,
  RANK() OVER (
    ORDER BY s.excess_over_history DESC, s.day_amount DESC, s.customer_id
  ) AS suspicious_rank
FROM suspicious s
JOIN cus c ON c.h01 = s.customer_id
ORDER BY
  suspicious_rank,
  s.customer_id,
  s.suspicious_date;