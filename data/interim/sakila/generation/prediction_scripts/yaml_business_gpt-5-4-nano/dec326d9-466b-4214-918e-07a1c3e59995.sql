WITH
params AS (
  SELECT
    DATE('now') AS today
),
payment_base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    p.p06 AS payment_datetime,
    DATE(p.p06) AS payment_day,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p03 AS staff_id,
    sf.o02 || ' ' || sf.o03 AS staff_name,
    sf.o07 AS staff_store_id,
    co.c02 AS country_name,
    ct.d02 AS city_name,
    r.q01 AS rental_id,
    i.n01 AS inventory_id,
    fc.l02 AS film_category_id
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN stf AS sf
    ON sf.o01 = p.p03
  JOIN adr AS ca
    ON ca.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = ca.e05
  JOIN cnt AS co
    ON co.c01 = ct.d03
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN inv AS i
    ON i.n01 = r.q03
  LEFT JOIN flc AS fc
    ON fc.l01 = i.n02
),
daily_customer AS (
  SELECT
    customer_id,
    customer_name,
    country_name,
    city_name,
    payment_day,
    SUM(payment_amount) AS day_total_amount,
    COUNT(*) AS day_payment_count,
    COUNT(DISTINCT staff_id) AS day_distinct_staff_count,
    COUNT(DISTINCT staff_store_id) AS day_distinct_store_count,
    COUNT(DISTINCT inventory_id) AS day_distinct_films_count
  FROM payment_base
  GROUP BY
    customer_id,
    customer_name,
    country_name,
    city_name,
    payment_day
),
windows AS (
  SELECT
    dc.customer_id,
    dc.customer_name,
    dc.country_name,
    dc.city_name,
    dc.payment_day AS window_start_day,
    DATE(dc.payment_day, '+6 day') AS window_end_day,

    SUM(d2.day_total_amount) AS window_total_amount,
    SUM(d2.day_payment_count) AS window_payment_count,
    SUM(d2.day_distinct_staff_count) AS window_distinct_staff_count_proxy,
    MAX(d2.day_distinct_staff_count) AS window_max_daily_staff_count,

    SUM(d2.day_distinct_store_count) AS window_distinct_store_count_proxy,
    MAX(d2.day_distinct_store_count) AS window_max_daily_store_count,

    SUM(d2.day_distinct_films_count) AS window_distinct_films_count_proxy
  FROM daily_customer AS dc
  JOIN daily_customer AS d2
    ON d2.customer_id = dc.customer_id
   AND d2.payment_day >= dc.payment_day
   AND d2.payment_day <= DATE(dc.payment_day, '+6 day')
  GROUP BY
    dc.customer_id,
    dc.customer_name,
    dc.country_name,
    dc.city_name,
    dc.payment_day
),
history_30d AS (
  SELECT
    w.customer_id,
    w.window_start_day,

    AVG(h.day_total_amount) AS avg_daily_amount_prev_30d,
    AVG(h.day_payment_count) AS avg_daily_payment_count_prev_30d,

    SUM(h.day_total_amount) / 30.0 AS avg_window_amount_prev_30d,
    SUM(h.day_payment_count) / 30.0 AS avg_window_payment_count_prev_30d,

    COUNT(*) AS history_days_count
  FROM windows AS w
  JOIN daily_customer AS h
    ON h.customer_id = w.customer_id
   AND h.payment_day >= DATE(w.window_start_day, '-30 day')
   AND h.payment_day < w.window_start_day
  GROUP BY
    w.customer_id,
    w.window_start_day
),
scored AS (
  SELECT
    w.*,
    h.avg_window_amount_prev_30d,
    h.avg_window_payment_count_prev_30d,
    h.history_days_count,

    CASE
      WHEN h.avg_window_amount_prev_30d > 0
      THEN w.window_total_amount / h.avg_window_amount_prev_30d
      ELSE NULL
    END AS amount_ratio_vs_history_window
  FROM windows AS w
  JOIN history_30d AS h
    ON h.customer_id = w.customer_id
   AND h.window_start_day = w.window_start_day
),
qualifying AS (
  SELECT
    s.*,
    DENSE_RANK() OVER (
      ORDER BY s.window_total_amount DESC
    ) AS suspicious_window_rank_by_amount
  FROM scored AS s
  WHERE s.history_days_count >= 1
    AND s.window_payment_count >= 5
    AND s.avg_window_amount_prev_30d IS NOT NULL
    AND s.avg_window_amount_prev_30d > 0
    AND s.window_total_amount >= 3.0 * s.avg_window_amount_prev_30d
)
SELECT
  q.customer_id,
  q.customer_name,
  q.country_name,
  q.city_name,
  q.window_start_day AS window_start_date,
  q.window_end_day AS window_end_date,

  q.window_payment_count AS window_payment_operations,
  ROUND(q.window_total_amount, 2) AS window_total_amount,
  ROUND(q.amount_ratio_vs_history_window, 2) AS amount_ratio_vs_prev_30d_avg_window,

  -- Вспомогательные (оценочные) агрегаты
  q.window_distinct_films_count_proxy AS distinct_films_in_window_proxy,

  q.suspicious_window_rank_by_amount AS client_rank_among_all_by_suspicious_amount
FROM qualifying AS q
ORDER BY
  q.window_total_amount DESC,
  q.customer_id,
  q.window_start_day;