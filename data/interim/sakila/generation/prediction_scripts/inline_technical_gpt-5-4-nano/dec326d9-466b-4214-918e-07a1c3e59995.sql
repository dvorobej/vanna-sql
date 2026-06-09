WITH pay_daily AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS day_date,
    COUNT(p.p01) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_sum
  FROM pay AS p
  GROUP BY
    p.p02,
    date(p.p06)
),
windows AS (
  SELECT
    pd.customer_id,
    pd.day_date AS window_end_date,
    SUM(pd_prev.day_sum) AS window_sum_7d,
    SUM(pd_prev.payment_count) AS window_payment_count_7d
  FROM pay_daily AS pd
  JOIN pay_daily AS pd_prev
    ON pd_prev.customer_id = pd.customer_id
   AND pd_prev.day_date > date(pd.day_date, '-7 days')
   AND pd_prev.day_date <= pd.day_date
  GROUP BY
    pd.customer_id,
    pd.day_date
),
windows_scored AS (
  SELECT
    w.*,
    AVG(w2.window_sum_7d) AS hist_avg_window_sum_7d,
    AVG(w2.window_payment_count_7d) AS hist_avg_window_payment_count_7d
  FROM windows AS w
  LEFT JOIN windows AS w2
    ON w2.customer_id = w.customer_id
   AND date(w2.window_end_date) < date(w.window_end_date, '-7 days')
   AND date(w2.window_end_date) >= date(w.window_end_date, '-37 days')
  GROUP BY
    w.customer_id,
    w.window_end_date,
    w.window_sum_7d,
    w.window_payment_count_7d
),
selected AS (
  SELECT
    ws.*,
    (ws.window_sum_7d / NULLIF(ws.hist_avg_window_sum_7d, 0)) AS ratio_to_hist_avg
  FROM windows_scored AS ws
  WHERE ws.hist_avg_window_sum_7d IS NOT NULL
    AND ws.hist_avg_window_sum_7d > 0
    AND ws.window_sum_7d >= 3.0 * ws.hist_avg_window_sum_7d
    AND ws.window_payment_count_7d >= 5
),
window_payments AS (
  SELECT
    s.customer_id,
    s.window_end_date,
    date(p.p06) AS payment_day,
    p.p01 AS payment_id,
    p.p05 AS payment_amount,
    p.p03 AS staff_id,
    r.q01 AS rental_id,
    r.q03 AS inventory_id,
    inv.n03 AS store_id,
    inv.n02 AS film_id
  FROM selected AS s
  JOIN pay AS p
    ON p.p02 = s.customer_id
   AND date(p.p06) > date(s.window_end_date, '-7 days')
   AND date(p.p06) <= s.window_end_date
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN inv AS inv
    ON inv.n01 = r.q03
),
films_in_window AS (
  SELECT
    wp.customer_id,
    wp.window_end_date,
    COUNT(DISTINCT wp.film_id) AS distinct_films_i01
  FROM window_payments wp
  GROUP BY
    wp.customer_id,
    wp.window_end_date
),
geo_info AS (
  SELECT
    c.h01 AS customer_id,
    cnt.c02 AS country,
    cty.d02 AS city
  FROM cus c
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ON cty.d01 = a.e05
  JOIN cnt ON cnt.c01 = cty.d03
)
SELECT
  s.customer_id,
  gi.country,
  gi.city,
  s.window_end_date AS suspicious_window_end_date,
  ROUND(s.window_sum_7d, 2) AS suspicious_window_sum_7d,
  s.window_payment_count_7d AS suspicious_window_payment_count_7d,
  COUNT(DISTINCT wp.staff_id) AS distinct_staff_count,
  COUNT(DISTINCT wp.store_id) AS distinct_store_count,
  MAX(wp.payment_day) AS last_payment_day_in_window,
  MIN(wp.payment_day) AS first_payment_day_in_window,
  MAX(wp.payment_amount) AS max_payment_amount_in_window,
  fiw.distinct_films_i01 AS distinct_films_count_i01,
  DENSE_RANK() OVER (
    ORDER BY s.window_sum_7d DESC
  ) AS suspicious_rank_over_all_customers
FROM selected s
JOIN window_payments wp
  ON wp.customer_id = s.customer_id
 AND wp.window_end_date = s.window_end_date
JOIN geo_info gi
  ON gi.customer_id = s.customer_id
LEFT JOIN films_in_window fiw
  ON fiw.customer_id = s.customer_id
 AND fiw.window_end_date = s.window_end_date
GROUP BY
  s.customer_id,
  gi.country,
  gi.city,
  s.window_end_date,
  s.window_sum_7d,
  s.window_payment_count_7d,
  fiw.distinct_films_i01
ORDER BY
  s.window_sum_7d DESC,
  s.customer_id,
  s.window_end_date;