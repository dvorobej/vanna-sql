SELECT DISTINCT country, month_start, country_p95_payment_sum
    FROM scored
) cp95
  ON cp95.country = x.country
 AND cp95.month_start = x.month_start
WHERE x.payment_sum >= 3.0 * x.personal_avg_prev_2_months
  AND x.payment_sum > x.country_p95_payment_sum
ORDER BY
    x.country,
    x.payment_month,
    x.customer_country_rank,
    x.payment_sum DESC;