SELECT DISTINCT
    wh.customer_id,
    wh.payment_date,
    wh.country_name,
    wh.city_name,
    wh.sum_last_7_days AS suspicious_window_sum,
    wh.cnt_last_7_days AS suspicious_window_payment_count,
    wh.avg_sum_prev_30d AS historical_avg_prev_30d_sum,
    wh.ratio_to_hist_avg
  FROM window_hits wh
  WHERE wh.cnt_last_7_days >= 5
    AND wh.avg_sum_prev_30d IS NOT NULL
    AND wh.avg_sum_prev_30d > 0
    AND wh.sum_last_7_days >= 3 * wh.avg_sum_prev_30d
),
staff_shop_and_film_counts AS (
  SELECT
    f.customer_id,
    f.payment_date,
    COUNT(DISTINCT pe.staff_id) AS distinct_staff_count,
    COUNT(DISTINCT r.q06) AS distinct_rental_staff_count,
    COUNT(DISTINCT i.n03) AS distinct_shop_count,
    COUNT(DISTINCT fc.l02) AS distinct_rented_film_count
  FROM filtered f
  JOIN p_enriched pe
    ON pe.customer_id = f.customer_id
   AND pe.payment_date >= date(f.payment_date, '-6 days')
   AND pe.payment_date <= f.payment_date
  LEFT JOIN ren r
    ON r.q01 = pe.rental_id
  LEFT JOIN inv i
    ON i.n01 = r.q03
  LEFT JOIN flc fc
    ON fc.l01 = i.n02
  GROUP BY f.customer_id, f.payment_date
),
suspicious_rank AS (
  SELECT
    f.*,
    DENSE_RANK() OVER (
      ORDER BY f.suspicious_window_sum DESC
    ) AS client_suspicious_amount_rank
  FROM filtered f
)
SELECT
  sr.customer_id,
  sr.payment_date,
  sr.country_name,
  sr.city_name,
  sr.suspicious_window_payment_count AS window_payment_count,
  ROUND(sr.suspicious_window_sum, 2) AS window_payment_sum,
  ROUND(sr.historical_avg_prev_30d_sum, 2) AS historical_avg_prev_30d_sum,
  sr.ratio_to_hist_avg AS sum_to_historical_ratio,
  sfc.distinct_staff_count AS distinct_staff_count_in_window,
  sfc.distinct_shop_count AS distinct_shop_count_in_window,
  sfc.distinct_rented_film_count AS distinct_rented_film_count_in_window,
  sr.client_suspicious_amount_rank
FROM suspicious_rank sr
LEFT JOIN staff_shop_and_film_counts sfc
  ON sfc.customer_id = sr.customer_id
 AND sfc.payment_date = sr.payment_date
ORDER BY
  sr.payment_date,
  sr.client_suspicious_amount_rank,
  sr.customer_id;