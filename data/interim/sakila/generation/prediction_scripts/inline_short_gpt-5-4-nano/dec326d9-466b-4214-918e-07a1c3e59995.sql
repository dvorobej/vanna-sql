WITH RECURSIVE
bounds AS (
  SELECT
    date(MIN(p06), 'start of day') AS min_dt,
    date(MAX(p06), 'start of day') AS max_dt
  FROM pay
),
days(dt) AS (
  SELECT min_dt FROM bounds WHERE min_dt IS NOT NULL
  UNION ALL
  SELECT date(dt, '+1 day') FROM days, bounds WHERE dt < max_dt
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    co.c01 AS country_id,
    co.c02 AS country_name,
    ci.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ci.d03
),
payment_enriched AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_day,
    CAST(p.p05 AS REAL) AS amount,
    p.p03 AS staff_id,
    s.o07 AS staff_store_id,
    COALESCE(i.n03, s.o07) AS payment_store_id,
    i.n02 AS film_id
  FROM pay AS p
  JOIN stf AS s ON s.o01 = p.p03
  LEFT JOIN ren AS r ON r.q01 = p.p04
  LEFT JOIN inv AS i ON i.n01 = r.q03
),
base_customer_day AS (
  SELECT
    cg.customer_id,
    cg.country_name,
    cg.city_name,
    d.dt AS window_end_day
  FROM customer_geo AS cg
  CROSS JOIN days AS d
),
window_agg AS (
  SELECT
    bcd.customer_id,
    bcd.country_name,
    bcd.city_name,
    bcd.window_end_day,
    SUM(pe.amount) AS window_7d_amount,
    COUNT(*) AS window_7d_payment_count,
    COUNT(DISTINCT pe.staff_id) AS window_7d_staff_count,
    COUNT(DISTINCT pe.payment_store_id) AS window_7d_store_count,
    COUNT(DISTINCT pe.film_id) AS window_7d_distinct_rented_films
  FROM base_customer_day AS bcd
  LEFT JOIN payment_enriched AS pe
    ON pe.customer_id = bcd.customer_id
   AND pe.payment_day >= date(bcd.window_end_day, '-6 day')
   AND pe.payment_day <= bcd.window_end_day
  GROUP BY
    bcd.customer_id,
    bcd.country_name,
    bcd.city_name,
    bcd.window_end_day
),
avg_30d AS (
  SELECT
    wa.customer_id,
    wa.window_end_day,
    AVG(daily.daily_amount) AS avg_daily_amount_30d
  FROM window_agg AS wa
  LEFT JOIN (
    SELECT
      pe.customer_id,
      date(pe.payment_day) AS day_dt,
      SUM(pe.amount) AS daily_amount
    FROM payment_enriched AS pe
    GROUP BY pe.customer_id, date(pe.payment_day)
  ) AS daily
    ON daily.customer_id = wa.customer_id
   AND daily.day_dt >= date(wa.window_end_day, '-30 day')
   AND daily.day_dt < date(wa.window_end_day, '-6 day')
  GROUP BY
    wa.customer_id,
    wa.window_end_day
),
scored AS (
  SELECT
    wa.*,
    a30.avg_daily_amount_30d,
    CASE
      WHEN a30.avg_daily_amount_30d > 0 THEN wa.window_7d_amount / (a30.avg_daily_amount_30d * 7)
      ELSE NULL
    END AS window_vs_avg_factor,
    PERCENT_RANK() OVER (
      PARTITION BY wa.country_name, wa.city_name, wa.window_end_day
      ORDER BY wa.window_7d_amount DESC
    ) AS suspicious_rank_in_loc
  FROM window_agg AS wa
  JOIN avg_30d AS a30
    ON a30.customer_id = wa.customer_id
   AND a30.window_end_day = wa.window_end_day
)
SELECT
  c.h03 AS first_name,
  c.h04 AS last_name,
  s.customer_id,
  s.country_name,
  s.city_name,
  s.window_end_day AS suspicious_window_end_date,
  s.window_7d_payment_count AS payment_count_7d,
  ROUND(s.window_7d_amount, 2) AS payment_sum_7d,
  ROUND(s.avg_daily_amount_30d, 2) AS avg_daily_payment_amount_30d,
  ROUND(s.window_vs_avg_factor, 2) AS window_vs_avg_factor,
  s.window_7d_staff_count AS staff_count_7d,
  s.window_7d_store_count AS store_count_7d,
  s.window_7d_distinct_rented_films AS distinct_rented_films_count_7d,
  s.suspicious_rank_in_loc AS suspicious_rank_by_sum_in_city_day
FROM scored AS s
JOIN cus AS c ON c.h01 = s.customer_id
WHERE s.avg_daily_amount_30d IS NOT NULL
  AND s.avg_daily_amount_30d > 0
  AND s.window_7d_amount > 3 * (s.avg_daily_amount_30d * 7)
ORDER BY
  s.window_end_day,
  s.country_name,
  s.city_name,
  payment_sum_7d DESC,
  s.customer_id;