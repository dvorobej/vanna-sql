SELECT AVG(pd2.daily_sum)
      FROM pay_daily AS pd2
      WHERE pd2.customer_id = pd.customer_id
        AND pd2.payment_date >= date(pd.payment_date, '-30 day')
        AND pd2.payment_date < pd.payment_date
    ) AS personal_avg_prev_30d
  FROM pay_daily AS pd
  JOIN customer_geo AS cg
    ON cg.customer_id = pd.customer_id
),
country_daily_avgs AS (
  SELECT
    dwa.*,
    (
      SELECT AVG(daily_sum)
      FROM pay_daily AS pd2
      JOIN customer_geo AS cg2
        ON cg2.customer_id = pd2.customer_id
      WHERE cg2.country_id = dwa.country_id
        AND pd2.payment_date = dwa.payment_date
    ) AS country_avg_daily_sum
  FROM daily_with_avgs AS dwa
),
suspicious_days AS (
  SELECT
    cda.*,
    dss.distinct_staff_count,
    dss.distinct_store_count,
    (cda.daily_sum - cda.personal_avg_prev_30d) AS deviation_from_personal_avg,
    (cda.daily_sum - cda.country_avg_daily_sum) AS deviation_from_country_avg,
    RANK() OVER (
      PARTITION BY cda.country_id, cda.payment_date
      ORDER BY cda.daily_sum DESC
    ) AS country_daily_rank_by_sum
  FROM country_daily_avgs AS cda
  JOIN daily_staff_store AS dss
    ON dss.customer_id = cda.customer_id
   AND dss.payment_date = cda.payment_date
  WHERE cda.personal_avg_prev_30d IS NOT NULL
    AND cda.personal_avg_prev_30d > 0
    AND cda.country_avg_daily_sum IS NOT NULL
    AND cda.country_avg_daily_sum > 0
    AND cda.daily_sum > 3.0 * cda.personal_avg_prev_30d
    AND cda.daily_sum > cda.country_avg_daily_sum
    AND (dss.distinct_staff_count > 1 OR dss.distinct_store_count > 1)
)
SELECT
  sd.customer_id,
  -- names
  c.h03 AS first_name,
  c.h04 AS last_name,
  sd.country_name,
  sd.city_name,
  sd.payment_date AS date,
  ROUND(sd.daily_sum, 2) AS day_total_sum,
  sd.payment_count AS day_payment_count,
  ROUND(sd.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
  ROUND(sd.deviation_from_country_avg, 2) AS deviation_from_country_avg,
  sd.distinct_staff_count AS distinct_staff_count,
  sd.distinct_store_count AS distinct_store_count,
  sd.country_daily_rank_by_sum AS suspicious_rank_in_country
FROM suspicious_days AS sd
JOIN cus AS c
  ON c.h01 = sd.customer_id
ORDER BY
  sd.country_name,
  sd.payment_date,
  sd.country_daily_rank_by_sum,
  sd.customer_id;