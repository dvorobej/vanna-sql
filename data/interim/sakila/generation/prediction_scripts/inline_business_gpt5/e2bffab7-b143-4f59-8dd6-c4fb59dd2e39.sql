WITH daily_payments AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    city.d02 AS city,
    country.c01 AS country_id,
    country.c02 AS country,
    DATE(p.p06) AS payment_day,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS payment_amount,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count,
    GROUP_CONCAT(DISTINCT p.p03) AS staff_ids,
    GROUP_CONCAT(DISTINCT s.o07) AS store_ids,
    COUNT(DISTINCT p.p04) AS linked_rental_count
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS city
    ON city.d01 = a.e05
  JOIN cnt AS country
    ON country.c01 = city.d03
  JOIN stf AS s
    ON s.o01 = p.p03
  GROUP BY
    c.h01,
    c.h03,
    c.h04,
    city.d02,
    country.c01,
    country.c02,
    DATE(p.p06)
),
daily_with_history AS (
  SELECT
    dp.*,
    (
      SELECT AVG(prev.payment_amount)
      FROM daily_payments AS prev
      WHERE prev.customer_id = dp.customer_id
        AND prev.payment_day >= DATE(dp.payment_day, '-30 day')
        AND prev.payment_day < dp.payment_day
    ) AS avg_30d_payment_amount,
    (
      SELECT AVG(prev.payment_count * 1.0)
      FROM daily_payments AS prev
      WHERE prev.customer_id = dp.customer_id
        AND prev.payment_day >= DATE(dp.payment_day, '-30 day')
        AND prev.payment_day < dp.payment_day
    ) AS avg_30d_payment_count,
    (
      SELECT COUNT(*)
      FROM daily_payments AS prev
      WHERE prev.customer_id = dp.customer_id
        AND prev.payment_day >= DATE(dp.payment_day, '-30 day')
        AND prev.payment_day < dp.payment_day
    ) AS history_days_30d
  FROM daily_payments AS dp
),
ranked_country_days AS (
  SELECT
    dwh.*,
    RANK() OVER (
      PARTITION BY dwh.country_id, dwh.payment_day
      ORDER BY dwh.payment_amount DESC
    ) AS country_day_amount_rank,
    COUNT(*) OVER (
      PARTITION BY dwh.country_id, dwh.payment_day
    ) AS country_day_customer_count
  FROM daily_with_history AS dwh
)
SELECT
  customer_id,
  first_name,
  last_name,
  city,
  country,
  payment_day,
  payment_count,
  ROUND(payment_amount, 2) AS payment_amount,
  ROUND(avg_30d_payment_count, 2) AS avg_30d_payment_count,
  ROUND(avg_30d_payment_amount, 2) AS avg_30d_payment_amount,
  ROUND(payment_count / NULLIF(avg_30d_payment_count, 0), 2) AS count_to_30d_avg_ratio,
  ROUND(payment_amount / NULLIF(avg_30d_payment_amount, 0), 2) AS amount_to_30d_avg_ratio,
  staff_count,
  staff_ids,
  store_count,
  store_ids,
  linked_rental_count,
  country_day_amount_rank,
  country_day_customer_count,
  CASE
    WHEN staff_count > 1 OR store_count > 1 THEN 1
    ELSE 0
  END AS multiple_staff_or_store_flag
FROM ranked_country_days
WHERE history_days_30d > 0
  AND avg_30d_payment_amount > 0
  AND avg_30d_payment_count > 0
  AND payment_amount >= avg_30d_payment_amount * 3
  AND payment_count >= avg_30d_payment_count * 3
  AND country_day_amount_rank <= CAST((country_day_customer_count + 19) / 20 AS INTEGER)
ORDER BY
  payment_day,
  country,
  country_day_amount_rank,
  payment_amount DESC,
  customer_id;