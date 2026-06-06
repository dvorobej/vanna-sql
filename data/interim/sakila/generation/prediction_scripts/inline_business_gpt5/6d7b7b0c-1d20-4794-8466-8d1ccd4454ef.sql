WITH payment_base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    stf.o07 AS store_id,
    CAST(p.p05 AS REAL) AS amount,
    p.p06 AS payment_ts,
    cus.h03 AS first_name,
    cus.h04 AS last_name,
    cty.d02 AS city,
    cnt.c02 AS country
  FROM pay AS p
  JOIN cus AS cus
    ON cus.h01 = p.p02
  JOIN adr AS adr
    ON adr.e01 = cus.h06
  JOIN cty AS cty
    ON cty.d01 = adr.e05
  JOIN cnt AS cnt
    ON cnt.c01 = cty.d03
  JOIN stf AS stf
    ON stf.o01 = p.p03
),
window_metrics AS (
  SELECT
    b.payment_id AS start_payment_id,
    b.customer_id,
    b.first_name,
    b.last_name,
    b.city,
    b.country,
    b.payment_ts AS window_start,
    datetime(b.payment_ts, '+24 hours') AS window_end,
    COUNT(w.payment_id) AS window_payment_count,
    SUM(w.amount) AS window_payment_amount,
    (
      SELECT COALESCE(SUM(p30.amount), 0) / 30.0
      FROM payment_base AS p30
      WHERE p30.customer_id = b.customer_id
        AND p30.payment_ts >= datetime(b.payment_ts, '-30 days')
        AND p30.payment_ts < b.payment_ts
    ) AS avg_daily_amount_prev_30d,
    (
      SELECT COUNT(*) / 30.0
      FROM payment_base AS p30
      WHERE p30.customer_id = b.customer_id
        AND p30.payment_ts >= datetime(b.payment_ts, '-30 days')
        AND p30.payment_ts < b.payment_ts
    ) AS avg_daily_count_prev_30d
  FROM payment_base AS b
  JOIN payment_base AS w
    ON w.customer_id = b.customer_id
   AND w.payment_ts >= b.payment_ts
   AND w.payment_ts < datetime(b.payment_ts, '+24 hours')
  GROUP BY
    b.payment_id,
    b.customer_id,
    b.first_name,
    b.last_name,
    b.city,
    b.country,
    b.payment_ts
),
last_payment_ranked AS (
  SELECT
    b.payment_id AS start_payment_id,
    w.payment_id AS last_payment_id,
    w.staff_id AS last_staff_id,
    w.store_id AS last_store_id,
    w.payment_ts AS last_payment_ts,
    ROW_NUMBER() OVER (
      PARTITION BY b.payment_id
      ORDER BY w.payment_ts DESC, w.payment_id DESC
    ) AS rn
  FROM payment_base AS b
  JOIN payment_base AS w
    ON w.customer_id = b.customer_id
   AND w.payment_ts >= b.payment_ts
   AND w.payment_ts < datetime(b.payment_ts, '+24 hours')
),
suspicious_windows AS (
  SELECT
    wm.*,
    lpr.last_payment_id,
    lpr.last_staff_id,
    lpr.last_store_id,
    lpr.last_payment_ts,
    wm.window_payment_amount / NULLIF(wm.avg_daily_amount_prev_30d, 0) AS amount_deviation_ratio,
    wm.window_payment_count / NULLIF(wm.avg_daily_count_prev_30d, 0) AS count_deviation_ratio
  FROM window_metrics AS wm
  JOIN last_payment_ranked AS lpr
    ON lpr.start_payment_id = wm.start_payment_id
   AND lpr.rn = 1
  WHERE wm.avg_daily_amount_prev_30d > 0
    AND wm.avg_daily_count_prev_30d > 0
    AND wm.window_payment_amount >= wm.avg_daily_amount_prev_30d * 3.0
    AND wm.window_payment_count >= wm.avg_daily_count_prev_30d * 3.0
)
SELECT
  customer_id,
  first_name,
  last_name,
  country,
  city,
  window_start,
  window_end,
  window_payment_count,
  ROUND(window_payment_amount, 2) AS window_payment_amount,
  ROUND(avg_daily_amount_prev_30d, 2) AS avg_daily_amount_prev_30d,
  ROUND(avg_daily_count_prev_30d, 2) AS avg_daily_count_prev_30d,
  last_staff_id,
  last_store_id,
  last_payment_id,
  last_payment_ts,
  ROUND(amount_deviation_ratio, 2) AS amount_deviation_ratio,
  ROUND(count_deviation_ratio, 2) AS count_deviation_ratio,
  RANK() OVER (
    ORDER BY amount_deviation_ratio DESC, count_deviation_ratio DESC, window_payment_amount DESC
  ) AS anomaly_rank
FROM suspicious_windows
ORDER BY
  anomaly_rank,
  window_start,
  customer_id;