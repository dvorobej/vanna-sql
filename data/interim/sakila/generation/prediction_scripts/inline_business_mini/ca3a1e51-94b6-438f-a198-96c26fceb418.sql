SELECT AVG(prev.day_amount)
            FROM daily_stats AS prev
            WHERE prev.customer_id = ds.customer_id
              AND prev.pay_day < ds.pay_day
              AND julianday(ds.pay_day) - julianday(prev.pay_day) <= 30
        ) AS avg_prev_30d_day_amount
    FROM daily_stats AS ds
),
qualified_days AS (
    SELECT
        dwh.*,
        ROUND(dwh.day_amount - dwh.avg_prev_30d_day_amount, 2) AS deviation_from_30d_avg,
        ROUND(dwh.day_amount / NULLIF(dwh.avg_prev_30d_day_amount, 0), 2) AS ratio_to_30d_avg,
        ROW_NUMBER() OVER (
            PARTITION BY dwh.customer_id
            ORDER BY (dwh.day_amount - dwh.avg_prev_30d_day_amount) DESC, dwh.pay_day DESC
        ) AS day_rank
    FROM daily_with_history AS dwh
    WHERE dwh.payment_count >= 3
      AND (dwh.distinct_staff_count >= 2 OR dwh.distinct_store_count >= 2)
      AND dwh.avg_prev_30d_day_amount IS NOT NULL
      AND dwh.day_amount > 2 * dwh.avg_prev_30d_day_amount
)
SELECT
    customer_id,
    customer_first_name,
    customer_last_name,
    city_name,
    country_name,
    pay_day,
    payment_count,
    ROUND(day_amount, 2) AS day_amount,
    distinct_staff_count,
    distinct_store_count,
    stores_used,
    staff_used,
    deviation_from_30d_avg,
    ratio_to_30d_avg,
    day_rank
FROM qualified_days
ORDER BY
    deviation_from_30d_avg DESC,
    customer_id,
    pay_day;