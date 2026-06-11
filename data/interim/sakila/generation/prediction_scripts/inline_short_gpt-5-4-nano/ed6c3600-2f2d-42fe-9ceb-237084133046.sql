WITH day_payments AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    COUNT(*) AS day_payment_count
  FROM pay AS p
  GROUP BY
    p.p02,
    date(p.p06)
),
daily_with_history AS (
  SELECT
    dp.*,
    (
      SELECT AVG(dp2.day_amount)
      FROM day_payments AS dp2
      WHERE dp2.customer_id = dp.customer_id
        AND dp2.payment_date >= date(dp.payment_date, '-30 days')
        AND dp2.payment_date <  dp.payment_date
    ) AS avg_prev_30d_amount,
    (
      SELECT AVG(dp2.day_payment_count * 1.0)
      FROM day_payments AS dp2
      WHERE dp2.customer_id = dp.customer_id
        AND dp2.payment_date >= date(dp.payment_date, '-30 days')
        AND dp2.payment_date <  dp.payment_date
    ) AS avg_prev_30d_count
  FROM day_payments AS dp
),
flagged_days AS (
  SELECT
    dwh.*,
    CASE
      WHEN dwh.avg_prev_30d_amount IS NULL OR dwh.avg_prev_30d_amount = 0 THEN NULL
      ELSE dwh.day_amount / dwh.avg_prev_30d_amount
    END AS amount_ratio,
    CASE
      WHEN dwh.avg_prev_30d_count IS NULL OR dwh.avg_prev_30d_count = 0 THEN NULL
      ELSE dwh.day_payment_count * 1.0 / dwh.avg_prev_30d_count
    END AS count_ratio
  FROM daily_with_history AS dwh
  WHERE dwh.avg_prev_30d_amount IS NOT NULL
    AND dwh.avg_prev_30d_amount > 0
    AND dwh.avg_prev_30d_count IS NOT NULL
    AND dwh.avg_prev_30d_count > 0
),
suspicious_cases AS (
  SELECT
    fd.customer_id,
    fd.payment_date,
    fd.day_amount,
    fd.day_payment_count,
    fd.amount_ratio,
    fd.count_ratio,
    (
      COALESCE(fd.amount_ratio, 0) * 0.7 +
      COALESCE(fd.count_ratio, 0) * 0.3
    ) AS risk_score
  FROM flagged_days AS fd
  WHERE fd.day_amount >= 3 * fd.avg_prev_30d_amount
     OR fd.day_payment_count >= 3 * fd.avg_prev_30d_count
)
SELECT
  sc.customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  sc.payment_date,
  ROUND(sc.day_amount, 2) AS day_amount,
  sc.day_payment_count,
  ROUND(sc.amount_ratio, 2) AS amount_ratio,
  ROUND(sc.count_ratio, 2) AS count_ratio,
  ROUND(sc.risk_score, 4) AS risk_score,
  DENSE_RANK() OVER (ORDER BY sc.risk_score DESC, sc.day_amount DESC) AS risk_rank
FROM suspicious_cases AS sc
JOIN cus AS c
  ON c.h01 = sc.customer_id
ORDER BY
  risk_rank,
  sc.payment_date,
  sc.day_amount DESC,
  sc.customer_id;