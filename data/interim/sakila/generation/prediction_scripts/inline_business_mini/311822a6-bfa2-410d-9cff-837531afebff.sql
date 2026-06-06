SELECT *
    FROM country_month_ranked
    WHERE prev_window_count >= 3
      AND prev30_avg_amount > 0
      AND prev30_avg_count > 0
      AND window_amount >= 3.0 * prev30_avg_amount
      AND window_payment_count >= 3.0 * prev30_avg_count
      AND (staff_count > 1 OR store_count > 1)
)
SELECT
    payment_month,
    customer_id,
    customer_name,
    country_name,
    city_name,
    window_start,
    window_end,
    ROUND(window_amount, 2) AS window_amount,
    window_payment_count,
    ROUND(prev30_avg_amount, 2) AS prev30_avg_amount,
    ROUND(prev30_avg_count, 2) AS prev30_avg_count,
    staff_count,
    store_count,
    month_country_rank
FROM suspicious
ORDER BY payment_month, month_country_rank, window_amount DESC, customer_id;