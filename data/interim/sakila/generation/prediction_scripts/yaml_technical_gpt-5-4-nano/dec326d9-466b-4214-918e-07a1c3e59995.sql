WITH win_base AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    c.h06 AS customer_address_id,
    date(p.p06) AS d,
    SUM(CAST(p.p05 AS REAL)) AS win_amount_7d,
    COUNT(p.p01) AS win_payment_count_7d
  FROM pay p
  JOIN cus c
    ON c.h01 = p.p02
  GROUP BY
    c.h01, c.h03, c.h04, c.h06, date(p.p06)
),
windows AS (
  SELECT
    wb.customer_id,
    wb.first_name,
    wb.last_name,
    wb.d AS window_start_date,
    (
      SELECT SUM(wb2.win_amount_7d)
      FROM win_base wb2
      WHERE wb2.customer_id = wb.customer_id
        AND wb2.d >= date(wb.d)
        AND wb2.d < date(wb.d, '+7 days')
    ) AS win_amount_7d,
    (
      SELECT SUM(wb2.win_payment_count_7d)
      FROM win_base wb2
      WHERE wb2.customer_id = wb.customer_id
        AND wb2.d >= date(wb.d)
        AND wb2.d < date(wb.d, '+7 days')
    ) AS win_payment_count_7d
  FROM win_base wb
),
windows_scored AS (
  SELECT
    w.*,
    (
      SELECT AVG(wb_prev.win_amount_7d)
      FROM win_base wb_prev
      WHERE wb_prev.customer_id = w.customer_id
        AND wb_prev.d >= date(w.window_start_date, '-30 days')
        AND wb_prev.d < date(w.window_start_date)
    ) AS avg_daily_amount_prev_30d,
    (
      SELECT AVG(wb_prev.win_payment_count_7d)
      FROM win_base wb_prev
      WHERE wb_prev.customer_id = w.customer_id
        AND wb_prev.d >= date(w.window_start_date, '-30 days')
        AND wb_prev.d < date(w.window_start_date)
    ) AS avg_daily_payment_count_prev_30d
  FROM windows w
),
qualifying_windows AS (
  SELECT
    ws.*,
    (ws.win_amount_7d / NULLIF(ws.avg_daily_amount_prev_30d * 7.0, 0)) AS amount_multiplier
  FROM windows_scored ws
  WHERE ws.avg_daily_amount_prev_30d IS NOT NULL
    AND ws.avg_daily_amount_prev_30d > 0
    AND ws.win_amount_7d >= 3.0 * ws.avg_daily_amount_prev_30d * 7.0
    AND ws.win_payment_count_7d >= 5
),
window_payments AS (
  SELECT
    p.p02 AS customer_id,
    q.window_start_date,
    p.p01 AS payment_id,
    p.p05 AS payment_amount,
    p.p06 AS payment_datetime,
    p.p03 AS staff_id,
    r.q01 AS rental_id,
    r.q03 AS inventory_id,
    s.o07 AS staff_store_id,
    i.n01 AS inv_copy_id,
    i.n02 AS film_id,
    i.n03 AS inventory_store_id,
    a.e01 AS address_id,
    co.c01 AS country_id
  FROM qualifying_windows q
  JOIN pay p
    ON p.p02 = q.customer_id
   AND date(p.p06) >= q.window_start_date
   AND date(p.p06) < date(q.window_start_date, '+7 days')
  JOIN ren r
    ON r.q01 = p.p04
  JOIN stf s
    ON s.o01 = p.p03
  JOIN inv i
    ON i.n01 = r.q03
  JOIN cus c
    ON c.h01 = p.p02
  JOIN adr a
    ON a.e01 = c.h06
  JOIN cty ct
    ON ct.d01 = a.e05
  JOIN cnt co
    ON co.c01 = ct.d03
),
window_film_counts AS (
  SELECT
    wp.customer_id,
    wp.window_start_date,
    COUNT(DISTINCT f.film_id) AS distinct_film_id_count
  FROM (
    SELECT DISTINCT
      wp2.customer_id,
      wp2.window_start_date,
      i.n02 AS film_id
    FROM window_payments wp2
    JOIN inv i
      ON i.n01 = wp2.inventory_id
    JOIN flm f
      ON f.i01 = i.n02
  ) f
  JOIN window_payments wp
    ON wp.customer_id = f.customer_id
   AND wp.window_start_date = f.window_start_date
  GROUP BY
    wp.customer_id,
    wp.window_start_date
),
window_people_places AS (
  SELECT
    wp.customer_id,
    wp.window_start_date,
    MAX(cat.cty.d02) AS city,
    MAX(cnt.c02) AS country,
    COUNT(DISTINCT wp.staff_id) AS distinct_staff_count,
    COUNT(DISTINCT wp.staff_store_id) AS distinct_staff_store_count,
    COUNT(DISTINCT wp.inventory_store_id) AS distinct_inventory_store_count,
    COUNT(DISTINCT wp.film_id) AS distinct_film_attempt_count
  FROM window_payments wp
  JOIN cus c
    ON c.h01 = wp.customer_id
  JOIN adr a
    ON a.e01 = c.h06
  JOIN cty cat
    ON cat.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = cat.d03
  GROUP BY
    wp.customer_id,
    wp.window_start_date
),
window_risk_output AS (
  SELECT
    qw.customer_id,
    qw.first_name,
    qw.last_name,
    qw.window_start_date,
    qw.win_payment_count_7d AS payment_count_7d,
    ROUND(qw.win_amount_7d, 2) AS suspicious_amount_7d,
    ROUND(qw.avg_daily_amount_prev_30d * 7.0, 2) AS historical_avg_amount_7d,
    ROUND(qw.win_amount_7d - qw.avg_daily_amount_prev_30d * 7.0, 2) AS excess_amount_7d,
    wp.city,
    wp.country,
    wp.distinct_staff_count,
    wp.distinct_staff_store_count,
    wp.distinct_inventory_store_count,
    COALESCE(wfc.distinct_film_id_count, 0) AS distinct_film_id_count,
    RANK() OVER (
      ORDER BY qw.win_amount_7d DESC
    ) AS suspicious_rank_by_amount
  FROM qualifying_windows qw
  LEFT JOIN window_people_places wp
    ON wp.customer_id = qw.customer_id
   AND wp.window_start_date = qw.window_start_date
  LEFT JOIN window_film_counts wfc
    ON wfc.customer_id = qw.customer_id
   AND wfc.window_start_date = qw.window_start_date
)
SELECT
  customer_id,
  first_name,
  last_name,
  window_start_date,
  payment_count_7d,
  suspicious_amount_7d,
  historical_avg_amount_7d,
  excess_amount_7d,
  city,
  country,
  distinct_staff_count,
  distinct_staff_store_count,
  distinct_inventory_store_count,
  distinct_film_id_count,
  suspicious_rank_by_amount
FROM window_risk_output
ORDER BY suspicious_amount_7d DESC, customer_id, window_start_date;