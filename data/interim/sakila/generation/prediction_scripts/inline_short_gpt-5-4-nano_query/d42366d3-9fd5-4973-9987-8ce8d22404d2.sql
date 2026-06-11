SELECT AVG(m2.payment_sum)
     FROM monthly AS m2
     WHERE m2.customer_id = m.customer_id
       AND m2.month_start >= date(m.month_start,'-2 months')
       AND m2.month_start <  date(m.month_start,'-0 months') ) AS personal_avg_prev_2_months_sum
  FROM monthly AS m
),
country_month_rank AS (
  SELECT
    customer_id,
    country,
    month_start,
    payment_sum,
    payment_count,
    off_home_staff_payment_share,
    distinct_staff_count,
    personal_avg_prev_2_months_sum,
    RANK() OVER (
      PARTITION BY country, month_start
      ORDER BY payment_sum DESC
    ) AS rnk_in_country_month,
    COUNT(*) OVER (
      PARTITION BY country, month_start
    ) AS cnt_in_country_month
  FROM monthly_with_personal
),
country_p95_by_month AS (
  -- threshold: keep top 5% within each (country, month)
  SELECT
    cm.country,
    cm.month_start,
    MIN(cm.payment_sum) AS payment_sum_p95
  FROM (
    SELECT
      country,
      month_start,
      payment_sum,
      rnk_in_country_month,
      cnt_in_country_month
    FROM country_month_rank
  ) AS cm
  WHERE cm.rnk_in_country_month >= ( (95.0 * cm.cnt_in_country_month + 99.0) / 100.0 )
     OR cm.rnk_in_country_month = cm.cnt_in_country_month  -- safety for edge cases
  GROUP BY cm.country, cm.month_start
),
final_scored AS (
  SELECT
    cmr.customer_id,
    cmr.country,
    cmr.month_start,
    cmr.payment_count,
    cmr.payment_sum,
    cmr.personal_avg_prev_2_months_sum,
    cmr.off_home_staff_payment_share,
    cmr.distinct_staff_count,
    cpp.payment_sum_p95,
    (cmr.payment_sum / NULLIF(cmr.personal_avg_prev_2_months_sum,0)) AS personal_sum_multiplier,
    RANK() OVER (
      PARTITION BY cmr.country, cmr.month_start
      ORDER BY cmr.payment_sum DESC
    ) AS client_rank_in_country_month
  FROM country_month_rank AS cmr
  JOIN country_p95_by_month AS cpp
    ON cpp.country = cmr.country
   AND cpp.month_start = cmr.month_start
)
SELECT
  customer_id,
  country,
  strftime('%Y-%m', month_start) AS payment_month,
  payment_count,
  ROUND(payment_sum, 2) AS payment_sum,
  ROUND(personal_avg_prev_2_months_sum, 2) AS personal_avg_prev_2_months_sum,
  ROUND(personal_sum_multiplier, 2) AS personal_sum_multiplier,
  ROUND(off_home_staff_payment_share, 4) AS off_home_staff_payment_share,
  distinct_staff_count,
  ROUND(payment_sum_p95, 2) AS country_payment_sum_p95,
  client_rank_in_country_month
FROM final_scored
WHERE personal_avg_prev_2_months_sum IS NOT NULL
  AND personal_avg_prev_2_months_sum > 0
  AND payment_sum >= 3.0 * personal_avg_prev_2_months_sum
  AND payment_sum > payment_sum_p95
ORDER BY
  country,
  payment_month,
  client_rank_in_country_month,
  customer_id;