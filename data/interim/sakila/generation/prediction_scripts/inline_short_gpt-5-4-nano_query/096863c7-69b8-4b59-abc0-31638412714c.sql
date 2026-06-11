SELECT AVG(pdp2.day_sum)
      FROM pay_daily_with_store_country AS pdp2
      WHERE pdp2.customer_id = pd.customer_id
        AND pdp2.payment_date >= DATE(pd.payment_date, '-30 day')
        AND pdp2.payment_date <  pd.payment_date
    ) AS personal_avg_prev_30d
  FROM pay_daily_with_store_country AS pd
  JOIN customer_geo AS cg ON cg.customer_id = pd.customer_id
),
country_daily_avg AS (
  SELECT
    dwa.country_id,
    dwa.payment_date,
    AVG(dwa.day_sum) AS country_avg_day_sum
  FROM daily_with_avgs AS dwa
  GROUP BY dwa.country_id, dwa.payment_date
),
ranked AS (
  SELECT
    dwa.*,
    cda.country_avg_day_sum,
    (dwa.day_sum - dwa.personal_avg_prev_30d) AS deviation_personal_avg,
    (dwa.day_sum - cda.country_avg_day_sum) AS deviation_country_avg,
    RANK() OVER (
      PARTITION BY dwa.country_id
      ORDER BY dwa.day_sum DESC
    ) AS suspicion_rank_in_country
  FROM daily_with_avgs AS dwa
  JOIN country_daily_avg AS cda
    ON cda.country_id = dwa.country_id
   AND cda.payment_date = dwa.payment_date
)
SELECT
  customer_id,
  first_name,
  last_name,
  country_name AS country,
  city,
  payment_date AS date,
  ROUND(day_sum, 2) AS day_sum,
  payment_count,
  ROUND(deviation_personal_avg, 2) AS deviation_from_personal_avg,
  ROUND(deviation_country_avg, 2) AS deviation_from_country_avg,
  distinct_staff_count AS staff_count,
  distinct_store_count AS store_count,
  suspicion_rank_in_country
FROM ranked
WHERE personal_avg_prev_30d IS NOT NULL
  AND personal_avg_prev_30d > 0
  AND day_sum > 3.0 * personal_avg_prev_30d
  AND day_sum > country_avg_day_sum
  AND (distinct_staff_count >= 2 OR distinct_store_count >= 2)
ORDER BY
  country,
  suspicion_rank_in_country,
  day_sum DESC,
  customer_id;