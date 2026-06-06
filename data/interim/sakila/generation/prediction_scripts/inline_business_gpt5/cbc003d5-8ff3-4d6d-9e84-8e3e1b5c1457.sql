WITH RECURSIVE
payment_base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    DATE(p.p06) AS payment_day,
    p.p06 AS payment_ts,
    CAST(p.p05 AS REAL) AS amount,
    p.p03 AS staff_id,
    stf.o07 AS store_id,
    cnt.c01 AS country_id,
    cnt.c02 AS country_name,
    cty.d02 AS city_name
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty
    ON cty.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = cty.d03
  JOIN stf
    ON stf.o01 = p.p03
),
bounds AS (
  SELECT
    DATE(MIN(payment_day)) AS min_day,
    DATE(MAX(payment_day)) AS max_day
  FROM payment_base
),
calendar(day) AS (
  SELECT min_day
  FROM bounds
  WHERE min_day IS NOT NULL

  UNION ALL

  SELECT DATE(day, '+1 day')
  FROM calendar, bounds
  WHERE day < max_day
),
customer_geo AS (
  SELECT DISTINCT
    customer_id,
    country_id,
    country_name,
    city_name
  FROM payment_base
),
customer_calendar AS (
  SELECT
    cg.customer_id,
    cg.country_id,
    cg.country_name,
    cg.city_name,
    cal.day AS payment_day
  FROM customer_geo AS cg
  CROSS JOIN calendar AS cal
),
daily_customer AS (
  SELECT
    cc.customer_id,
    cc.country_id,
    cc.country_name,
    cc.city_name,
    cc.payment_day,
    COALESCE(SUM(pb.amount), 0.0) AS daily_amount,
    COUNT(pb.payment_id) AS daily_payment_count
  FROM customer_calendar AS cc
  LEFT JOIN payment_base AS pb
    ON pb.customer_id = cc.customer_id
   AND pb.payment_day = cc.payment_day
  GROUP BY
    cc.customer_id,
    cc.country_id,
    cc.country_name,
    cc.city_name,
    cc.payment_day
),
window_metrics AS (
  SELECT
    dc.customer_id,
    dc.country_id,
    dc.country_name,
    dc.city_name,
    dc.payment_day AS window_start,
    DATE(dc.payment_day, '+6 day') AS window_end,
    SUM(dc2.daily_amount) AS window_amount,
    SUM(dc2.daily_payment_count) AS window_payment_count
  FROM daily_customer AS dc
  JOIN daily_customer AS dc2
    ON dc2.customer_id = dc.customer_id
   AND dc2.payment_day >= dc.payment_day
   AND dc2.payment_day < DATE(dc.payment_day, '+7 day')
  GROUP BY
    dc.customer_id,
    dc.country_id,
    dc.country_name,
    dc.city_name,
    dc.payment_day
),
window_staff_store AS (
  SELECT
    wm.customer_id,
    wm.window_start,
    COUNT(DISTINCT pb.staff_id) AS staff_count,
    COUNT(DISTINCT pb.store_id) AS store_count
  FROM window_metrics AS wm
  LEFT JOIN payment_base AS pb
    ON pb.customer_id = wm.customer_id
   AND pb.payment_day >= wm.window_start
   AND pb.payment_day <= wm.window_end
  GROUP BY
    wm.customer_id,
    wm.window_start
),
window_with_baseline AS (
  SELECT
    wm.*,
    wss.staff_count,
    wss.store_count,
    (
      SELECT AVG(prev.window_amount)
      FROM window_metrics AS prev
      WHERE prev.customer_id = wm.customer_id
        AND prev.window_start >= DATE(wm.window_start, '-30 day')
        AND prev.window_start < wm.window_start
    ) AS customer_prev30_avg_7d_amount,
    (
      SELECT COUNT(*)
      FROM window_metrics AS prev
      WHERE prev.customer_id = wm.customer_id
        AND prev.window_start >= DATE(wm.window_start, '-30 day')
        AND prev.window_start < wm.window_start
    ) AS customer_prev30_window_count
  FROM window_metrics AS wm
  JOIN window_staff_store AS wss
    ON wss.customer_id = wm.customer_id
   AND wss.window_start = wm.window_start
),
country_ranked AS (
  SELECT
    wwb.*,
    AVG(wwb.window_amount) OVER (
      PARTITION BY wwb.country_id, wwb.window_start
    ) AS country_avg_7d_amount,
    ROW_NUMBER() OVER (
      PARTITION BY wwb.country_id, wwb.window_start
      ORDER BY wwb.window_amount
    ) AS country_amount_rn,
    COUNT(*) OVER (
      PARTITION BY wwb.country_id, wwb.window_start
    ) AS country_customer_count
  FROM window_with_baseline AS wwb
),
country_p95 AS (
  SELECT
    country_id,
    window_start,
    MIN(window_amount) AS country_p95_7d_amount
  FROM country_ranked
  WHERE country_amount_rn >= CAST((95 * country_customer_count + 99) / 100 AS INTEGER)
  GROUP BY
    country_id,
    window_start
),
scored AS (
  SELECT
    cr.customer_id,
    cr.country_name,
    cr.city_name,
    cr.window_start,
    cr.window_end,
    cr.window_amount,
    cr.window_payment_count,
    cr.staff_count,
    cr.store_count,
    cr.customer_prev30_avg_7d_amount,
    cr.country_avg_7d_amount,
    cp.country_p95_7d_amount,
    cr.window_amount / NULLIF(cr.customer_prev30_avg_7d_amount, 0) AS ratio_to_customer_baseline,
    cr.window_amount / NULLIF(cr.country_avg_7d_amount, 0) AS ratio_to_country_avg,
    cr.window_amount - cr.customer_prev30_avg_7d_amount AS deviation_from_customer_baseline
  FROM country_ranked AS cr
  JOIN country_p95 AS cp
    ON cp.country_id = cr.country_id
   AND cp.window_start = cr.window_start
)
SELECT
  s.customer_id,
  cus.h03 AS first_name,
  cus.h04 AS last_name,
  s.country_name AS country,
  s.city_name AS city,
  s.window_start,
  s.window_end,
  ROUND(s.window_amount, 2) AS window_7d_amount,
  s.window_payment_count,
  s.staff_count,
  s.store_count,
  ROUND(s.customer_prev30_avg_7d_amount, 2) AS customer_prev30_avg_7d_amount,
  ROUND(s.country_avg_7d_amount, 2) AS country_avg_7d_amount,
  ROUND(s.country_p95_7d_amount, 2) AS country_p95_7d_amount,
  ROUND(s.ratio_to_customer_baseline, 2) AS ratio_to_customer_baseline,
  ROUND(s.ratio_to_country_avg, 2) AS ratio_to_country_avg,
  RANK() OVER (
    ORDER BY
      s.ratio_to_customer_baseline DESC,
      s.ratio_to_country_avg DESC,
      s.window_amount DESC
  ) AS suspicious_rank
FROM scored AS s
JOIN cus
  ON cus.h01 = s.customer_id
WHERE s.customer_prev30_window_count >= 7
  AND s.customer_prev30_avg_7d_amount > 0
  AND s.country_avg_7d_amount > 0
  AND s.window_payment_count > 0
  AND s.window_amount >= 3.0 * s.customer_prev30_avg_7d_amount
  AND s.window_amount > s.country_avg_7d_amount
  AND s.window_amount >= s.country_p95_7d_amount
  AND (s.staff_count > 1 OR s.store_count > 1)
ORDER BY
  suspicious_rank,
  s.window_start,
  s.customer_id;