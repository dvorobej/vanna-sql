SELECT SUM(p3.payment_amount)
       FROM pay_with_movie AS p3
      WHERE p3.customer_id = p2.customer_id
        AND p3.payment_ts >= datetime(p2.payment_day_ts, '-6 days')
        AND p3.payment_ts <  datetime(date(p2.payment_day_ts, '+1 day')) ) AS rolling_sum_7d,

    (SELECT COUNT(*)
       FROM pay_with_movie AS p3
      WHERE p3.customer_id = p2.customer_id
        AND p3.payment_ts >= datetime(p2.payment_day_ts, '-6 days')
        AND p3.payment_ts <  datetime(date(p2.payment_day_ts, '+1 day')) ) AS rolling_count_7d,

    -- historical previous 30 days before the window day
    (SELECT AVG(p3.payment_amount)
       FROM pay_with_movie AS p3
      WHERE p3.customer_id = p2.customer_id
        AND p3.payment_ts >= datetime(p2.payment_day_ts, '-36 days')
        AND p3.payment_ts <  datetime(p2.payment_day_ts, '-6 days')
    ) AS hist_avg_amount_prev_30d,

    (SELECT AVG(p3.payment_amount)
       FROM pay_with_movie AS p3
      WHERE p3.customer_id = p2.customer_id
        AND p3.payment_ts >= datetime(p2.payment_day_ts, '-36 days')
        AND p3.payment_ts <  datetime(p2.payment_day_ts, '-6 days')
    ) AS hist_avg_amount_prev_30d_dup
  FROM (
    SELECT
      p.payment_day,
      p.payment_ts,
      p.customer_id
    FROM pay_with_movie AS p
    GROUP BY p.customer_id, p.payment_day, p.payment_ts
  ) AS p2
  JOIN customer_geo AS cg
    ON cg.customer_id = p2.customer_id
  -- alias fix
  JOIN (SELECT 1) dummy ON 1=1
),
candidate_days AS (
  SELECT
    w.customer_id,
    w.window_day,
    w.country_name,
    w.city_name,
    w.rolling_sum_7d,
    w.rolling_count_7d,
    w.hist_avg_amount_prev_30d
  FROM windowed AS w
  WHERE w.hist_avg_amount_prev_30d IS NOT NULL
),
qualified AS (
  SELECT *
  FROM candidate_days
  WHERE rolling_count_7d >= 5
    AND hist_avg_amount_prev_30d > 0
    AND rolling_sum_7d >= 3.0 * hist_avg_amount_prev_30d * rolling_count_7d
),
detail AS (
  SELECT
    q.customer_id,
    q.window_day,
    q.country_name,
    q.city_name,

    q.rolling_count_7d AS payment_count_7d,
    ROUND(q.rolling_sum_7d, 2) AS payment_sum_7d,

    -- distinct staff in the 7-day window
    (SELECT COUNT(DISTINCT p3.staff_id)
       FROM pay_with_movie AS p3
      WHERE p3.customer_id = q.customer_id
        AND p3.payment_ts >= datetime(q.window_day, '-6 days')
        AND p3.payment_ts <  datetime(date(q.window_day, '+1 day'))
    ) AS distinct_staff_count_7d,

    -- distinct stores in the 7-day window (store from client -> pay joins via cus.h02)
    (SELECT COUNT(DISTINCT cu.h02)
       FROM pay_with_movie AS p3
       JOIN cus AS cu ON cu.h01 = p3.customer_id
      WHERE p3.customer_id = q.customer_id
        AND p3.payment_ts >= datetime(q.window_day, '-6 days')
        AND p3.payment_ts <  datetime(date(q.window_day, '+1 day'))
    ) AS distinct_store_count_7d,

    -- distinct rentals/movies count in the 7-day window
    (SELECT COUNT(DISTINCT p3.movie_id)
       FROM pay_with_movie AS p3
      WHERE p3.customer_id = q.customer_id
        AND p3.payment_ts >= datetime(q.window_day, '-6 days')
        AND p3.payment_ts <  datetime(date(q.window_day, '+1 day'))
        AND p3.movie_id IS NOT NULL
    ) AS distinct_rented_movies_count_7d
  FROM qualified AS q
),
ranked AS (
  SELECT
    d.*,
    RANK() OVER (
      ORDER BY d.payment_sum_7d DESC
    ) AS customer_suspicious_rank
  FROM detail AS d
)
SELECT
  r.customer_suspicious_rank,
  r.customer_id,
  r.window_day AS payment_day,
  r.country_name AS country,
  r.city_name AS city,
  r.payment_count_7d AS payment_count_7d,
  r.payment_sum_7d AS payment_sum_7d,
  r.distinct_staff_count_7d AS distinct_staff_count_7d,
  r.distinct_store_count_7d AS distinct_store_count_7d,
  r.distinct_rented_movies_count_7d AS distinct_rented_movies_count_7d
FROM ranked AS r
ORDER BY r.payment_sum_7d DESC, r.customer_id, r.payment_day;