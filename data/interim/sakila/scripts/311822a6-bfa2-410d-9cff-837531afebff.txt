WITH RECURSIVE
bounds AS (
  SELECT
    date(MIN(p06), '-30 day') AS min_date,
    date(MAX(p06)) AS max_date
  FROM pay
),
calendar(dt) AS (
  SELECT min_date
  FROM bounds
  UNION ALL
  SELECT date(dt, '+1 day')
  FROM calendar
  CROSS JOIN bounds
  WHERE dt < max_date
),
customer_bounds AS (
  SELECT
    p02 AS customer_id,
    date(MIN(p06)) AS min_date,
    date(MAX(p06)) AS max_date
  FROM pay
  GROUP BY p02
),
window_starts AS (
  SELECT
    cb.customer_id,
    c.dt AS window_start
  FROM customer_bounds cb
  JOIN calendar c
    ON c.dt BETWEEN cb.min_date AND cb.max_date
),
raw_payments AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    s.o07 AS store_id,
    date(p.p06) AS payment_date,
    p.p05 AS amount
  FROM pay p
  JOIN stf s
    ON s.o01 = p.p03
),
window_metrics AS (
  SELECT
    ws.customer_id,
    ws.window_start,
    date(ws.window_start, '+6 day') AS window_end,
    COALESCE(SUM(
      CASE
        WHEN rp.payment_date >= ws.window_start
         AND rp.payment_date < date(ws.window_start, '+7 day')
        THEN rp.amount
        ELSE 0
      END
    ), 0) AS window_payment_sum,
    COUNT(
      CASE
        WHEN rp.payment_date >= ws.window_start
         AND rp.payment_date < date(ws.window_start, '+7 day')
        THEN rp.payment_id
      END
    ) AS window_payment_count,
    COUNT(DISTINCT
      CASE
        WHEN rp.payment_date >= ws.window_start
         AND rp.payment_date < date(ws.window_start, '+7 day')
        THEN rp.staff_id
      END
    ) AS staff_count,
    COUNT(DISTINCT
      CASE
        WHEN rp.payment_date >= ws.window_start
         AND rp.payment_date < date(ws.window_start, '+7 day')
        THEN rp.store_id
      END
    ) AS store_count,
    COALESCE(SUM(
      CASE
        WHEN rp.payment_date >= date(ws.window_start, '-30 day')
         AND rp.payment_date < ws.window_start
        THEN rp.amount
        ELSE 0
      END
    ), 0) * 7.0 / 30.0 AS avg_30d_payment_sum,
    COUNT(
      CASE
        WHEN rp.payment_date >= date(ws.window_start, '-30 day')
         AND rp.payment_date < ws.window_start
        THEN rp.payment_id
      END
    ) * 7.0 / 30.0 AS avg_30d_payment_count
  FROM window_starts ws
  LEFT JOIN raw_payments rp
    ON rp.customer_id = ws.customer_id
   AND rp.payment_date >= date(ws.window_start, '-30 day')
   AND rp.payment_date < date(ws.window_start, '+7 day')
  GROUP BY
    ws.customer_id,
    ws.window_start
),
suspicious_windows AS (
  SELECT
    strftime('%Y-%m', wm.window_start) AS month,
    wm.customer_id,
    wm.window_start,
    wm.window_end,
    wm.window_payment_sum,
    wm.window_payment_count,
    wm.avg_30d_payment_sum,
    wm.avg_30d_payment_count,
    wm.staff_count,
    wm.store_count,
    wm.window_payment_sum / wm.avg_30d_payment_sum AS amount_exceedance_ratio,
    wm.window_payment_count / wm.avg_30d_payment_count AS count_exceedance_ratio
  FROM window_metrics wm
  WHERE wm.avg_30d_payment_sum > 0
    AND wm.avg_30d_payment_count > 0
    AND wm.window_payment_sum >= 3.0 * wm.avg_30d_payment_sum
    AND wm.window_payment_count >= 3.0 * wm.avg_30d_payment_count
    AND (wm.staff_count > 1 OR wm.store_count > 1)
),
best_customer_month_window AS (
  SELECT *
  FROM (
    SELECT
      sw.*,
      ROW_NUMBER() OVER (
        PARTITION BY sw.month, sw.customer_id
        ORDER BY
          sw.amount_exceedance_ratio DESC,
          sw.count_exceedance_ratio DESC,
          sw.window_payment_sum DESC,
          sw.window_payment_count DESC,
          sw.window_start
      ) AS rn
    FROM suspicious_windows sw
  )
  WHERE rn = 1
)
SELECT
  bcmw.month,
  bcmw.customer_id,
  cus.h03 || ' ' || cus.h04 AS customer_name,
  cty.d02 AS city,
  cnt.c02 AS country,
  bcmw.window_start,
  bcmw.window_end,
  ROUND(bcmw.window_payment_sum, 2) AS suspicious_7d_payment_sum,
  bcmw.window_payment_count AS suspicious_7d_payment_count,
  ROUND(bcmw.avg_30d_payment_sum, 2) AS avg_30d_payment_sum,
  ROUND(bcmw.avg_30d_payment_count, 2) AS avg_30d_payment_count,
  bcmw.staff_count,
  bcmw.store_count,
  ROUND(bcmw.amount_exceedance_ratio, 2) AS amount_exceedance_ratio,
  ROUND(bcmw.count_exceedance_ratio, 2) AS count_exceedance_ratio,
  RANK() OVER (
    PARTITION BY bcmw.month
    ORDER BY bcmw.amount_exceedance_ratio DESC, bcmw.count_exceedance_ratio DESC
  ) AS customer_month_rank
FROM best_customer_month_window bcmw
JOIN cus
  ON cus.h01 = bcmw.customer_id
JOIN adr
  ON adr.e01 = cus.h06
JOIN cty
  ON cty.d01 = adr.e05
JOIN cnt
  ON cnt.c01 = cty.d03
ORDER BY
  bcmw.month,
  customer_month_rank,
  bcmw.customer_id;