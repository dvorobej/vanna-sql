WITH payment_enriched AS (
  SELECT
    p.p02 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    date(p.p06) AS payment_day,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p03 AS staff_id,
    s.o07 AS store_id,
    cn.c01 AS country_id
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS cn
    ON cn.c01 = ct.d03
  JOIN stf AS s
    ON s.o01 = p.p03
),
daily_customer AS (
  SELECT
    customer_id,
    first_name,
    last_name,
    country_id,
    payment_day,
    COUNT(*) AS payment_count,
    SUM(payment_amount) AS day_total_amount,
    COUNT(DISTINCT staff_id) AS distinct_staff_count,
    COUNT(DISTINCT store_id) AS distinct_store_count
  FROM payment_enriched
  GROUP BY
    customer_id,
    first_name,
    last_name,
    country_id,
    payment_day
),
daily_with_baseline AS (
  SELECT
    dc.*,
    (
      SELECT AVG(dc2.day_total_amount)
      FROM daily_customer AS dc2
      WHERE dc2.customer_id = dc.customer_id
        AND dc2.payment_day >= date(dc.payment_day, '-30 days')
        AND dc2.payment_day < dc.payment_day
    ) AS avg_prev_30d_customer
  FROM daily_customer AS dc
),
country_daily_avg AS (
  SELECT
    dd.country_id,
    dd.payment_day,
    AVG(dd.day_total_amount) AS country_avg_daily_amount
  FROM (
    SELECT
      customer_id,
      country_id,
      payment_day,
      day_total_amount
    FROM daily_customer
  ) AS dd
  GROUP BY
    dd.country_id,
    dd.payment_day
),
scored AS (
  SELECT
    dwb.*,
    cda.country_avg_daily_amount,
    dwb.day_total_amount / NULLIF(dwb.avg_prev_30d_customer, 0) AS customer_ratio_to_prev_avg
  FROM daily_with_baseline AS dwb
  JOIN country_daily_avg AS cda
    ON cda.country_id = dwb.country_id
   AND cda.payment_day = dwb.payment_day
)
SELECT
  s.customer_id,
  s.first_name,
  s.last_name,
  s.country_id,
  s.payment_day AS date,
  s.payment_count AS payments_in_day,
  ROUND(s.day_total_amount, 2) AS day_total_amount,
  ROUND(s.avg_prev_30d_customer, 2) AS avg_prev_30d_customer,
  ROUND(s.country_avg_daily_amount, 2) AS avg_country_daily_amount,
  ROUND(s.customer_ratio_to_prev_avg, 2) AS ratio_to_prev_avg,
  RANK() OVER (
    PARTITION BY s.country_id
    ORDER BY s.day_total_amount DESC
  ) AS amount_rank_in_country,
  CASE
    WHEN (s.distinct_staff_count > 1 OR s.distinct_store_count > 1) THEN 1
    ELSE 0
  END AS has_multiple_staff_or_stores,
  CASE
    WHEN s.customer_ratio_to_prev_avg > 3
     AND s.day_total_amount > s.country_avg_daily_amount
    THEN 1 ELSE 0
  END AS suspicious_activity
FROM scored AS s
WHERE s.avg_prev_30d_customer IS NOT NULL
  AND s.customer_ratio_to_prev_avg > 3
  AND s.day_total_amount > s.country_avg_daily_amount
ORDER BY
  s.country_id,
  amount_rank_in_country,
  s.day_total_amount DESC;