SELECT *
  FROM windowed
  WHERE hist_payment_count > 0
    AND window_payment_count >= 5
    AND window_payment_sum >= 3.0 * hist_avg_payment_amount
),
details AS (
  SELECT
    f.customer_id,
    f.payment_ts AS window_end_ts,

    f.first_name,
    f.last_name,
    f.country_name,
    f.city_name,

    f.window_payment_count,
    ROUND(f.window_payment_sum, 2) AS window_payment_sum,

    COUNT(DISTINCT e.staff_id) AS distinct_staff_count,
    COUNT(DISTINCT e.inventory_store_id) AS distinct_store_count,
    COUNT(DISTINCT e.film_id) AS distinct_rented_films_count,

    SUM(CASE WHEN e.staff_id IS NOT NULL THEN 1 ELSE 0 END) AS total_payments_in_window
  FROM filtered AS f
  JOIN events AS e
    ON e.customer_id = f.customer_id
   AND e.payment_ts >= datetime(f.payment_ts, '-6 days')
   AND e.payment_ts <= f.payment_ts
  GROUP BY
    f.customer_id, f.payment_ts, f.first_name, f.last_name, f.country_name, f.city_name,
    f.window_payment_count, f.window_payment_sum
),
ranked AS (
  SELECT
    d.*,
    DENSE_RANK() OVER (
      ORDER BY d.window_payment_sum DESC
    ) AS suspicious_client_rank
  FROM details AS d
)
SELECT
  suspicious_client_rank AS client_rank,
  customer_id,
  first_name,
  last_name,
  country_name,
  city_name,
  window_end_ts AS window_end_datetime,
  window_payment_count,
  window_payment_sum,
  distinct_staff_count,
  distinct_store_count,
  distinct_rented_films_count
FROM ranked
ORDER BY
  window_payment_sum DESC,
  window_end_ts DESC,
  customer_id;