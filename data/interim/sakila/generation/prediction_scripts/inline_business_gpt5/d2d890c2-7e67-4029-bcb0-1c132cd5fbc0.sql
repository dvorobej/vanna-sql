WITH payment_enriched AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    DATE(p.p06) AS payment_date,
    CAST(p.p05 AS REAL) AS amount,
    p.p03 AS staff_id,
    stf.o07 AS store_id,
    cnt.c01 AS country_id,
    cnt.c02 AS country,
    cty.d02 AS city
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty
    ON cty.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = cty.d03
  JOIN stf
    ON stf.o01 = p.p03
),
customer_daily AS (
  SELECT
    customer_id,
    country_id,
    country,
    city,
    payment_date,
    COUNT(*) AS payment_count,
    SUM(amount) AS daily_amount,
    COUNT(DISTINCT staff_id) AS staff_count,
    COUNT(DISTINCT store_id) AS store_count
  FROM payment_enriched
  GROUP BY
    customer_id,
    country_id,
    country,
    city,
    payment_date
),
daily_with_history AS (
  SELECT
    cd.*,
    (
      SELECT COALESCE(SUM(cd2.daily_amount), 0) / 30.0
      FROM customer_daily AS cd2
      WHERE cd2.customer_id = cd.customer_id
        AND cd2.payment_date >= DATE(cd.payment_date, '-30 day')
        AND cd2.payment_date < cd.payment_date
    ) AS personal_avg_30d,
    (
      SELECT COUNT(*)
      FROM customer_daily AS cd2
      WHERE cd2.customer_id = cd.customer_id
        AND cd2.payment_date >= DATE(cd.payment_date, '-30 day')
        AND cd2.payment_date < cd.payment_date
    ) AS history_payment_days
  FROM customer_daily AS cd
),
country_scored AS (
  SELECT
    dwh.*,
    AVG(dwh.daily_amount) OVER (
      PARTITION BY dwh.country_id, dwh.payment_date
    ) AS country_avg_daily_amount,
    RANK() OVER (
      PARTITION BY dwh.country_id, dwh.payment_date
      ORDER BY dwh.daily_amount DESC
    ) AS country_day_amount_rank,
    COUNT(*) OVER (
      PARTITION BY dwh.country_id, dwh.payment_date
    ) AS country_day_customer_count
  FROM daily_with_history AS dwh
),
suspicious_days AS (
  SELECT
    *,
    daily_amount / NULLIF(personal_avg_30d, 0) AS personal_deviation_ratio,
    daily_amount / NULLIF(country_avg_daily_amount, 0) AS country_deviation_ratio
  FROM country_scored
  WHERE history_payment_days >= 5
    AND personal_avg_30d > 0
    AND daily_amount >= personal_avg_30d * 3.0
    AND country_day_amount_rank <= ((country_day_customer_count + 19) / 20)
)
SELECT
  RANK() OVER (
    ORDER BY
      personal_deviation_ratio DESC,
      country_deviation_ratio DESC,
      daily_amount DESC
  ) AS suspicion_rank,
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  sd.country,
  sd.city,
  sd.payment_date,
  sd.payment_count,
  ROUND(sd.daily_amount, 2) AS daily_amount,
  ROUND(sd.personal_avg_30d, 2) AS personal_avg_30d,
  ROUND(sd.country_avg_daily_amount, 2) AS country_avg_daily_amount,
  ROUND(sd.personal_deviation_ratio, 2) AS personal_deviation_ratio,
  ROUND(sd.country_deviation_ratio, 2) AS country_deviation_ratio,
  sd.staff_count,
  sd.store_count,
  sd.country_day_amount_rank,
  sd.country_day_customer_count
FROM suspicious_days AS sd
JOIN cus AS c
  ON c.h01 = sd.customer_id
ORDER BY
  suspicion_rank,
  sd.payment_date,
  sd.customer_id;