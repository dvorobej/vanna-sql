WITH day_payments AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    date(p.p06) AS payment_day,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p03 AS staff_id,
    st.o07 AS store_id,
    COUNT(*) OVER (PARTITION BY p.p02, date(p.p06)) AS day_payment_count
  FROM pay AS p
  JOIN stf AS st
    ON st.o01 = p.p03
),
daily_customer AS (
  SELECT
    customer_id,
    payment_day,
    SUM(payment_amount) AS day_total_amount,
    COUNT(*) AS day_payment_count,
    COUNT(DISTINCT staff_id) AS staff_count,
    COUNT(DISTINCT store_id) AS store_count
  FROM (
    SELECT
      p.p02 AS customer_id,
      date(p.p06) AS payment_day,
      CAST(p.p05 AS REAL) AS payment_amount,
      p.p03 AS staff_id,
      st.o07 AS store_id
    FROM pay AS p
    JOIN stf AS st
      ON st.o01 = p.p03
  ) x
  GROUP BY customer_id, payment_day
),
with_prev_30 AS (
  SELECT
    dc.*,
    (
      SELECT AVG(d2.day_total_amount)
      FROM daily_customer AS d2
      WHERE d2.customer_id = dc.customer_id
        AND d2.payment_day >= date(dc.payment_day, '-30 days')
        AND d2.payment_day < dc.payment_day
    ) AS avg_prev_30d_amount,
    (
      SELECT AVG(1.0 * d2.day_payment_count)
      FROM daily_customer AS d2
      WHERE d2.customer_id = dc.customer_id
        AND d2.payment_day >= date(dc.payment_day, '-30 days')
        AND d2.payment_day < dc.payment_day
    ) AS avg_prev_30d_count
  FROM daily_customer AS dc
),
scored AS (
  SELECT
    w.*,
    CASE
      WHEN w.avg_prev_30d_amount IS NULL OR w.avg_prev_30d_amount <= 0 THEN NULL
      ELSE w.day_total_amount / w.avg_prev_30d_amount
    END AS amount_ratio,
    CASE
      WHEN w.avg_prev_30d_count IS NULL OR w.avg_prev_30d_count <= 0 THEN NULL
      ELSE w.day_payment_count / w.avg_prev_30d_count
    END AS count_ratio
  FROM with_prev_30 AS w
  WHERE w.avg_prev_30d_amount IS NOT NULL
),
flagged AS (
  SELECT
    s.*,
    CASE
      WHEN s.amount_ratio >= 3 AND s.count_ratio >= 2 THEN 3
      WHEN s.amount_ratio >= 3 OR s.count_ratio >= 2 THEN 2
      WHEN s.amount_ratio >= 2 THEN 1
      ELSE 0
    END AS suspicion_level,
    (
      COALESCE(s.amount_ratio, 0) * 0.7 +
      COALESCE(s.count_ratio, 0) * 0.3 +
      COALESCE(1.0 * s.store_count / 10.0, 0) * 0.05 +
      COALESCE(1.0 * s.staff_count / 10.0, 0) * 0.05
    ) AS risk_score
  FROM scored AS s
  WHERE
    (s.amount_ratio >= 3 OR s.count_ratio >= 2)
    AND s.day_payment_count >= 3
    AND s.day_total_amount > 0
),
ranked AS (
  SELECT
    f.*,
    RANK() OVER (ORDER BY f.risk_score DESC, f.day_total_amount DESC, f.customer_id) AS risk_rank
  FROM flagged AS f
)
SELECT
  r.customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  r.payment_day,
  ROUND(r.day_total_amount, 2) AS day_total_amount,
  r.day_payment_count,
  r.staff_count,
  r.store_count,
  ROUND(r.avg_prev_30d_amount, 2) AS avg_prev_30d_amount,
  ROUND(r.amount_ratio, 2) AS amount_ratio,
  ROUND(r.avg_prev_30d_count, 2) AS avg_prev_30d_count,
  ROUND(r.count_ratio, 2) AS count_ratio,
  r.suspicion_level,
  ROUND(r.risk_score, 4) AS risk_score,
  r.risk_rank
FROM ranked AS r
JOIN cus AS c
  ON c.h01 = r.customer_id
ORDER BY
  r.risk_rank,
  r.payment_day DESC,
  r.day_total_amount DESC;