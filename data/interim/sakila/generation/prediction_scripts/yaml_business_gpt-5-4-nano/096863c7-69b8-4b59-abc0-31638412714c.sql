SELECT AVG(dc_prev.daily_amount)
      FROM daily_client AS dc_prev
      WHERE dc_prev.customer_id = dc.customer_id
        AND dc_prev.payment_day < dc.payment_day
        AND dc_prev.payment_day >= DATE(dc.payment_day, '-30 days')
    ) AS avg_daily_amount_prev_30d
  FROM daily_client AS dc
),
country_daily AS (
  SELECT
    pg.customer_country_id,
    pg.payment_day,
    SUM(pg.payment_amount) AS country_daily_amount,
    COUNT(*) AS country_payments_count
  FROM payment_geo AS pg
  GROUP BY
    pg.customer_country_id,
    pg.payment_day
),
country_daily_with_avg AS (
  SELECT
    cd.*,
    (
      SELECT AVG(cd_prev.country_daily_amount)
      FROM country_daily AS cd_prev
      WHERE cd_prev.customer_country_id = cd.customer_country_id
        AND cd_prev.payment_day < cd.payment_day
        AND cd_prev.payment_day >= DATE(cd.payment_day, '-30 days')
    ) AS avg_country_daily_amount_prev_30d
  FROM country_daily AS cd
),
joined AS (
  SELECT
    dch.customer_id,
    dch.customer_city,
    dch.customer_country,
    dch.payment_day,
    dch.payment_count,
    dch.daily_amount,
    dch.staff_count,
    dch.store_count,
    dch.avg_daily_amount_prev_30d,
    cda.avg_country_daily_amount_prev_30d,
    (dch.daily_amount - dch.avg_daily_amount_prev_30d) AS deviation_from_personal_avg,
    (dch.daily_amount - cda.avg_country_daily_amount_prev_30d) AS deviation_from_country_avg,
    ROW_NUMBER() OVER (
      PARTITION BY dch.customer_country_id, dch.payment_day
      ORDER BY dch.daily_amount DESC
    ) AS day_rank_in_country
  FROM daily_client_with_history AS dch
  JOIN country_daily_with_avg AS cda
    ON cda.customer_country_id = dch.customer_country_id
   AND cda.payment_day = dch.payment_day
  WHERE dch.avg_daily_amount_prev_30d IS NOT NULL
    AND cda.avg_country_daily_amount_prev_30d IS NOT NULL
)
SELECT
  j.customer_id,
  c.h03 || ' ' || c.h04 AS customer_name,
  j.customer_city,
  j.customer_country,
  j.payment_day,
  j.payment_count,
  ROUND(j.daily_amount, 2) AS daily_amount,
  ROUND(j.avg_daily_amount_prev_30d, 2) AS personal_avg_daily_amount_prev_30d,
  ROUND(j.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
  ROUND(j.avg_country_daily_amount_prev_30d, 2) AS country_avg_daily_amount_prev_30d,
  ROUND(j.deviation_from_country_avg, 2) AS deviation_from_country_avg,
  j.staff_count,
  j.store_count,
  j.day_rank_in_country AS suspicious_day_rank_in_country
FROM joined AS j
JOIN cus AS c
  ON c.h01 = j.customer_id
WHERE
  j.daily_amount >= 3 * j.avg_daily_amount_prev_30d
  AND j.daily_amount > j.avg_country_daily_amount_prev_30d
ORDER BY
  j.customer_country,
  j.payment_day,
  j.daily_amount DESC,
  j.customer_id;