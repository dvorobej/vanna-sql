WITH RECURSIVE
params AS (
  SELECT 24.0 AS window_hours, 30.0 AS history_days, 3.0 AS anomaly_mult
),
pay_enriched AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    s.o07 AS store_id,
    p.p04 AS rental_id,
    CAST(p.p05 AS REAL) AS amount,
    p.p06 AS payment_ts,
    date(p.p06) AS payment_day,
    c.h03 || ' ' || c.h04 AS customer_name,
    c.h05 AS email,
    ct.d02 AS city_name,
    cn.c02 AS country_name,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, p.p06, p.p01
      ORDER BY p.p06 DESC, p.p01 DESC
    ) AS rn_same_ts
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS cn
    ON cn.c01 = ct.d03
  JOIN stf AS s
    ON s.o01 = p.p03
),
daily_history AS (
  SELECT
    pe.customer_id,
    pe.payment_day,
    SUM(pe.amount) AS day_amount,
    COUNT(*) AS day_count
  FROM pay_enriched AS pe
  GROUP BY
    pe.customer_id,
    pe.payment_day
),
history_stats AS (
  SELECT
    dh.customer_id,
    dh.payment_day,
    AVG(dh2.day_amount) AS avg_30d_day_amount,
    AVG(dh2.day_count) AS avg_30d_day_count
  FROM daily_history AS dh
  LEFT JOIN daily_history AS dh2
    ON dh2.customer_id = dh.customer_id
   AND dh2.payment_day >= date(dh.payment_day, '-30 day')
   AND dh2.payment_day < dh.payment_day
  GROUP BY
    dh.customer_id,
    dh.payment_day
),
window_starts AS (
  SELECT DISTINCT
    customer_id,
    datetime(payment_ts) AS window_start
  FROM pay_enriched
),
window_metrics AS (
  SELECT
    ws.customer_id,
    ws.window_start,
    datetime(ws.window_start, '+24 hours') AS window_end,
    SUM(CASE
      WHEN pe.payment_ts >= ws.window_start
       AND pe.payment_ts < datetime(ws.window_start, '+24 hours')
      THEN pe.amount ELSE 0 END) AS window_amount,
    COUNT(CASE
      WHEN pe.payment_ts >= ws.window_start
       AND pe.payment_ts < datetime(ws.window_start, '+24 hours')
      THEN 1 END) AS window_count,
    COUNT(DISTINCT CASE
      WHEN pe.payment_ts >= ws.window_start
       AND pe.payment_ts < datetime(ws.window_start, '+24 hours')
      THEN pe.staff_id END) AS staff_count,
    COUNT(DISTINCT CASE
      WHEN pe.payment_ts >= ws.window_start
       AND pe.payment_ts < datetime(ws.window_start, '+24 hours')
      THEN pe.store_id END) AS store_count,
    MAX(CASE
      WHEN pe.payment_ts >= ws.window_start
       AND pe.payment_ts < datetime(ws.window_start, '+24 hours')
      THEN pe.payment_ts END) AS last_payment_ts
  FROM window_starts AS ws
  JOIN pay_enriched AS pe
    ON pe.customer_id = ws.customer_id
   AND pe.payment_ts >= datetime(ws.window_start, '-30 day')
   AND pe.payment_ts < datetime(ws.window_start, '+24 hours')
  GROUP BY
    ws.customer_id,
    ws.window_start
),
window_last_payment AS (
  SELECT
    wm.customer_id,
    wm.window_start,
    pe.payment_id AS last_payment_id,
    pe.staff_id AS last_staff_id,
    pe.store_id AS last_store_id,
    pe.payment_ts AS last_payment_ts
  FROM window_metrics AS wm
  JOIN pay_enriched AS pe
    ON pe.customer_id = wm.customer_id
   AND pe.payment_ts = wm.last_payment_ts
),
scored AS (
  SELECT
    wm.*,
    hs.avg_30d_day_amount,
    hs.avg_30d_day_count,
    CASE
      WHEN hs.avg_30d_day_amount IS NULL OR hs.avg_30d_day_amount = 0 THEN NULL
      ELSE wm.window_amount / hs.avg_30d_day_amount
    END AS amount_ratio,
    CASE
      WHEN hs.avg_30d_day_count IS NULL OR hs.avg_30d_day_count = 0 THEN NULL
      ELSE wm.window_count / hs.avg_30d_day_count
    END AS count_ratio
  FROM window_metrics AS wm
  JOIN history_stats AS hs
    ON hs.customer_id = wm.customer_id
   AND hs.payment_day = date(wm.window_start)
)
SELECT
  s.customer_id,
  pe.customer_name,
  pe.email,
  pe.city_name,
  pe.country_name,
  s.window_start,
  s.window_end,
  ROUND(s.window_amount, 2) AS window_amount,
  s.window_count,
  ROUND(s.avg_30d_day_amount, 2) AS avg_30d_day_amount,
  ROUND(s.avg_30d_day_count, 2) AS avg_30d_day_count,
  ROUND(s.window_amount - s.avg_30d_day_amount, 2) AS deviation_amount,
  ROUND(s.window_count - s.avg_30d_day_count, 2) AS deviation_count,
  s.staff_count,
  s.store_count,
  wlp.last_store_id,
  wlp.last_staff_id,
  wlp.last_payment_ts,
  RANK() OVER (
    ORDER BY (s.window_amount - s.avg_30d_day_amount) DESC,
             (s.window_count - s.avg_30d_day_count) DESC
  ) AS deviation_rank
FROM scored AS s
JOIN pay_enriched AS pe
  ON pe.customer_id = s.customer_id
LEFT JOIN window_last_payment AS wlp
  ON wlp.customer_id = s.customer_id
 AND wlp.window_start = s.window_start
WHERE s.avg_30d_day_amount IS NOT NULL
  AND s.avg_30d_day_count IS NOT NULL
  AND s.window_count >= 3
  AND s.window_amount >= params.anomaly_mult * s.avg_30d_day_amount
  AND s.window_count >= params.anomaly_mult * s.avg_30d_day_count
  AND (s.staff_count > 1 OR s.store_count > 1)
GROUP BY s.customer_id, s.window_start
ORDER BY deviation_rank, s.customer_id, s.window_start;