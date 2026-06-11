SELECT AVG(w_prev.window_total_amount)
            FROM windowed w_prev
            WHERE w_prev.customer_id = w.customer_id
              AND w_prev.window_start_day >= DATE(w.window_start_day, '-30 day')
              AND w_prev.window_start_day < w.window_start_day
        ) AS avg_hist_daily_total_amount
    FROM windowed w
),
suspicious AS (
    SELECT
        s.*,
        DENSE_RANK() OVER (
            ORDER BY s.window_total_amount DESC
        ) AS suspicious_customer_rank_by_window_sum_global
    FROM scored s
    WHERE s.avg_hist_daily_total_amount IS NOT NULL
      AND s.window_payment_count >= 5
      AND s.window_total_amount >= 3.0 * s.avg_hist_daily_total_amount
)
SELECT
    sp.customer_id,
    sp.country_name,
    sp.city_name,
    sp.window_start_day AS window_day,
    sp.window_payment_count AS payment_count_in_window,
    ROUND(sp.window_total_amount, 2) AS payment_sum_in_window,
    sp.window_distinct_staff_count AS distinct_staff_count_in_window,
    sp.window_distinct_store_count AS distinct_store_count_in_window,
    sp.window_distinct_films_count AS distinct_films_count_in_window,
    sp.suspicious_customer_rank_by_window_sum_global AS suspicious_rank_in_all_customers
FROM suspicious sp
ORDER BY
    sp.payment_sum_in_window DESC,
    sp.payment_count_in_window DESC,
    sp.customer_id,
    sp.window_day;