SELECT AVG(dwgp.day_amount)
      FROM daily_with_geo dwgp
      WHERE dwgp.customer_id = dwg.customer_id
        AND dwgp.payment_date >= date(dwg.payment_date, '-30 day')
        AND dwgp.payment_date <  dwg.payment_date
    ) AS personal_avg_prev30
  FROM daily_with_geo dwg
),
country_daily_avg_prev AS (
  SELECT
    d1.country_id,
    d1.payment_date,
    AVG(d2.day_amount) AS country_avg_prev_days
  FROM daily_with_personal_prev30 d1
  JOIN daily_with_personal_prev30 d2
    ON d2.country_id = d1.country_id
   AND d2.payment_date >= date(d1.payment_date, '-30 day')
   AND d2.payment_date <  d1.payment_date
  GROUP BY
    d1.country_id,
    d1.payment_date
),
daily_scored AS (
  SELECT
    dwp.*,
    cda.country_avg_prev_days,
    (dwp.day_amount - dwp.personal_avg_prev30) AS deviation_personal,
    (dwp.day_amount - cda.country_avg_prev_days) AS deviation_country
  FROM daily_with_personal_prev30 dwp
  JOIN country_daily_avg_prev cda
    ON cda.country_id = dwp.country_id
   AND cda.payment_date = dwp.payment_date
),
filtered AS (
  SELECT
    ds.*,
    RANK() OVER (
      PARTITION BY ds.country_id
      ORDER BY ds.day_amount DESC
    ) AS country_suspicious_rank
  FROM daily_scored ds
  WHERE ds.personal_avg_prev30 IS NOT NULL
    AND ds.personal_avg_prev30 > 0
    AND ds.day_amount > 3.0 * ds.personal_avg_prev30
    AND ds.country_avg_prev_days IS NOT NULL
    AND ds.country_avg_prev_days > 0
    AND ds.day_amount > ds.country_avg_prev_days
    AND (ds.staff_count >= 2 OR ds.store_count >= 2)
)
SELECT
  customer_id,
  first_name,
  last_name,
  country,
  city,
  payment_date AS date,
  ROUND(day_amount, 2) AS day_sum,
  payment_count,
  ROUND(deviation_personal, 2) AS deviation_from_personal_avg,
  ROUND(deviation_country, 2) AS deviation_from_country_avg,
  staff_count AS distinct_staff_count,
  store_count AS distinct_store_count,
  country_suspicious_rank AS country_rank_by_suspicious_sum
FROM filtered
ORDER BY
  country,
  country_suspicious_rank,
  payment_date,
  last_name,
  first_name;