WITH daily_base AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS day_date,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT r.q03) AS rented_films_count
  FROM pay AS p
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  GROUP BY
    p.p02,
    date(p.p06)
),
daily_with_history AS (
  SELECT
    db.*,
    (
      SELECT AVG(db2.day_amount)
      FROM daily_base AS db2
      WHERE db2.customer_id = db.customer_id
        AND db2.day_date >= date(db.day_date, '-30 days')
        AND db2.day_date < db.day_date
    ) AS avg_prev_30d_amount,
    (
      SELECT AVG(db2.payment_count * 1.0)
      FROM daily_base AS db2
      WHERE db2.customer_id = db.customer_id
        AND db2.day_date >= date(db.day_date, '-30 days')
        AND db2.day_date < db.day_date
    ) AS avg_prev_30d_payment_count
  FROM daily_base AS db
),
scored AS (
  SELECT
    dwh.*,
    CASE
      WHEN dwh.avg_prev_30d_amount > 0
      THEN (dwh.day_amount / dwh.avg_prev_30d_amount)
      ELSE NULL
    END AS amount_ratio,
    CASE
      WHEN dwh.avg_prev_30d_payment_count > 0
      THEN (dwh.payment_count * 1.0 / dwh.avg_prev_30d_payment_count)
      ELSE NULL
    END AS count_ratio
  FROM daily_with_history AS dwh
),
suspicious AS (
  SELECT
    s.*,
    (
      COALESCE(s.amount_ratio, 0) * 0.6 +
      COALESCE(s.count_ratio, 0) * 0.4 +
      COALESCE(s.staff_count, 0) * 0.05 +
      COALESCE(s.rented_films_count, 0) * 0.05
    ) AS risk_score
  FROM scored AS s
  WHERE s.avg_prev_30d_amount IS NOT NULL
    AND s.avg_prev_30d_amount > 0
    AND s.avg_prev_30d_payment_count IS NOT NULL
    AND s.avg_prev_30d_payment_count > 0
    AND s.day_amount >= 2.0 * s.avg_prev_30d_amount
    AND s.payment_count >= 3
),
ranked AS (
  SELECT
    s.*,
    DENSE_RANK() OVER (
      ORDER BY s.risk_score DESC, s.day_amount DESC, s.customer_id, s.day_date
    ) AS risk_rank
  FROM suspicious AS s
)
SELECT
  r.customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  r.day_date AS suspicious_day,
  ROUND(r.day_amount, 2) AS day_amount,
  r.payment_count,
  r.staff_count,
  r.rented_films_count,
  ROUND(r.avg_prev_30d_amount, 2) AS avg_prev_30d_amount,
  ROUND(r.amount_ratio, 2) AS amount_ratio,
  ROUND(r.risk_score, 4) AS risk_score,
  r.risk_rank
FROM ranked AS r
JOIN cus AS c
  ON c.h01 = r.customer_id
ORDER BY
  r.risk_rank,
  r.day_amount DESC,
  r.day_date DESC,
  r.customer_id;