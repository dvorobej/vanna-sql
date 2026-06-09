WITH daily AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS day_date,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT p.p04) AS rental_count
  FROM pay AS p
  GROUP BY
    p.p02,
    date(p.p06)
),
with_history AS (
  SELECT
    d.*,
    (
      SELECT AVG(d2.day_amount)
      FROM daily AS d2
      WHERE d2.customer_id = d.customer_id
        AND d2.day_date >= date(d.day_date, '-30 days')
        AND d2.day_date <  d.day_date
    ) AS avg_prev_30d_amount,
    (
      SELECT AVG(d2.payment_count * 1.0)
      FROM daily AS d2
      WHERE d2.customer_id = d.customer_id
        AND d2.day_date >= date(d.day_date, '-30 days')
        AND d2.day_date <  d.day_date
    ) AS avg_prev_30d_payment_count
  FROM daily AS d
),
suspicious AS (
  SELECT
    wh.*,
    CASE
      WHEN wh.avg_prev_30d_amount > 0
      THEN wh.day_amount / wh.avg_prev_30d_amount
    END AS amount_ratio,
    CASE
      WHEN wh.avg_prev_30d_payment_count > 0
      THEN wh.payment_count / wh.avg_prev_30d_payment_count
    END AS count_ratio
  FROM with_history AS wh
  WHERE wh.avg_prev_30d_amount IS NOT NULL
    AND wh.avg_prev_30d_amount > 0
    AND wh.day_amount >= 3.0 * wh.avg_prev_30d_amount
    AND wh.payment_count >= 3
),
ranked AS (
  SELECT
    s.*,
    (
      COALESCE(s.amount_ratio, 0) * 0.6 +
      COALESCE(s.count_ratio, 0) * 0.3 +
      COALESCE(s.staff_count, 0) * 0.1
    ) AS risk_score
  FROM suspicious AS s
)
SELECT
  r.customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  r.day_date,
  ROUND(r.day_amount, 2) AS day_amount,
  r.payment_count,
  r.staff_count,
  r.rental_count,
  ROUND(r.avg_prev_30d_amount, 2) AS avg_prev_30d_amount,
  ROUND(r.amount_ratio, 2) AS amount_ratio,
  ROUND(r.avg_prev_30d_payment_count, 2) AS avg_prev_30d_payment_count,
  ROUND(r.count_ratio, 2) AS count_ratio,
  ROUND(r.risk_score, 4) AS risk_score,
  RANK() OVER (ORDER BY r.risk_score DESC, r.day_amount DESC, r.customer_id) AS risk_rank
FROM ranked AS r
JOIN cus AS c
  ON c.h01 = r.customer_id
ORDER BY
  risk_rank,
  r.day_date DESC,
  r.customer_id;