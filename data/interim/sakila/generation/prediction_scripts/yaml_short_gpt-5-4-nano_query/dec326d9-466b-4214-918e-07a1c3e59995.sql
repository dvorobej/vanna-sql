SELECT DISTINCT
    h.customer_id,
    h.customer_name,
    h.country,
    h.city,
    h.payment_date,

    h.win_sum_7d AS suspicious_window_sum,
    h.win_cnt_7d AS suspicious_window_payments,

    h.hist_avg_sum_prev_30d AS personal_hist_avg_sum_prev_30d
  FROM hist h
  WHERE h.hist_avg_sum_prev_30d IS NOT NULL
    AND h.win_cnt_7d >= 5
    AND h.win_sum_7d >= 3 * h.hist_avg_sum_prev_30d
),
window_details AS (
  SELECT
    se.customer_id,
    se.payment_date,

    GROUP_CONCAT(DISTINCT bd.staff_id) AS staff_ids,
    COUNT(DISTINCT bd.staff_id) AS distinct_staff_count,

    GROUP_CONCAT(DISTINCT bd.customer_home_store_id) AS home_store_ids_in_payments,
    COUNT(DISTINCT bd.customer_home_store_id) AS distinct_home_store_count,

    GROUP_CONCAT(DISTINCT bd.rental_id) AS rental_ids,
    COUNT(DISTINCT bd.rental_id) AS distinct_rental_count,

    COUNT(DISTINCT fa.k01) AS distinct_actors_in_window
  FROM suspicious_events se
  JOIN base bd
    ON bd.customer_id = se.customer_id
   AND bd.payment_date BETWEEN date(se.payment_date, '-6 day') AND se.payment_date
  JOIN ren r ON r.q01 = bd.rental_id
  JOIN inv i ON i.n01 = r.q03
  JOIN flc fc ON fc.l01 = i.n02
  JOIN fla fa ON fa.k02 = flc.l01
  GROUP BY se.customer_id, se.payment_date
),
top_ranks AS (
  SELECT
    se.*,
    RANK() OVER (
      ORDER BY se.suspicious_window_sum DESC
    ) AS suspicious_customer_rank_by_sum
  FROM suspicious_events se
)
SELECT
  tr.customer_id,
  tr.customer_name,
  tr.country,
  tr.city,
  tr.payment_date AS window_end_date,
  ROUND(tr.suspicious_window_sum, 2) AS window_sum_7d,
  tr.suspicious_window_payments AS window_payment_count,
  ROUND(tr.personal_hist_avg_sum_prev_30d, 2) AS personal_hist_avg_sum_prev_30d,
  wd.distinct_staff_count AS distinct_staff_count,
  wd.distinct_home_store_count AS distinct_store_count,
  wd.distinct_actors_in_window AS distinct_rented_films_count,
  tr.suspicious_customer_rank_by_sum
FROM top_ranks tr
LEFT JOIN window_details wd
  ON wd.customer_id = tr.customer_id
 AND wd.payment_date = tr.payment_date
ORDER BY
  tr.suspicious_customer_rank_by_sum,
  tr.suspicious_window_sum DESC,
  tr.customer_id;