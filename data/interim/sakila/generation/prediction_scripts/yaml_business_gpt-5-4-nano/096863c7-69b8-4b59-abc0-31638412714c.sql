SELECT AVG(dc2.day_amount)
      FROM daily_customer AS dc2
      WHERE dc2.customer_id = dc.customer_id
        AND dc2.payment_day >= DATE(dc.payment_day, '-30 days')
        AND dc2.payment_day < dc.payment_day
    ), 0.0) AS avg_prev_30d_day_amount
  FROM daily_customer AS dc
),
daily_country AS (
  SELECT
    customer_country_id,
    customer_country,
    payment_day,
    AVG(day_amount) AS country_avg_day_amount
  FROM daily_customer
  GROUP BY
    customer_country_id,
    customer_country,
    payment_day
),
suspicious_days AS (
  SELECT
    dch.*,
    dc2.country_avg_day_amount,
    (dch.day_amount - dch.avg_prev_30d_day_amount) AS deviation_from_personal_avg,
    CASE
      WHEN dch.avg_prev_30d_day_amount > 0
      THEN (dch.day_amount - dch.avg_prev_30d_day_amount) / dch.avg_prev_30d_day_amount
    END AS personal_deviation_ratio,
    CASE
      WHEN dc2.country_avg_day_amount > 0
      THEN (dch.day_amount - dc2.country_avg_day_amount) / dc2.country_avg_day_amount
    END AS country_deviation_ratio
  FROM daily_customer_with_history AS dch
  JOIN daily_country AS dc2
    ON dc2.customer_country_id = dch.customer_country_id
   AND dc2.payment_day = dch.payment_day
  WHERE dch.avg_prev_30d_day_amount > 0
)
SELECT
  sd.customer_id,
  sd.customer_first_name,
  sd.customer_last_name,
  sd.customer_country,
  sd.customer_city,
  sd.payment_day,
  sd.payment_count,
  ROUND(sd.day_amount, 2) AS day_amount,
  ROUND(sd.avg_prev_30d_day_amount, 2) AS personal_avg_day_amount_prev_30d,
  ROUND(sd.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
  ROUND(sd.country_avg_day_amount, 2) AS country_avg_day_amount,
  ROUND(sd.day_amount - sd.country_avg_day_amount, 2) AS deviation_from_country_avg,
  sd.staff_count,
  sd.store_count,
  RANK() OVER (
    PARTITION BY sd.customer_country_id
    ORDER BY sd.day_amount DESC
  ) AS suspicious_sum_rank_within_country
FROM suspicious_days AS sd
WHERE sd.payment_count > 0
  AND sd.day_amount >= 3.0 * sd.avg_prev_30d_day_amount
  AND sd.day_amount > sd.country_avg_day_amount
ORDER BY
  sd.customer_country,
  suspicious_sum_rank_within_country,
  sd.payment_day,
  sd.customer_id;