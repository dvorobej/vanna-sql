WITH payment_base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    city.d02 AS city,
    city.d03 AS country_id,
    p.p03 AS staff_id,
    st.o07 AS store_id,
    p.p05 AS amount,
    date(p.p06) AS payment_date
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS city
    ON city.d01 = a.e05
  JOIN stf AS st
    ON st.o01 = p.p03
),
daily_activity AS (
  SELECT
    customer_id,
    first_name,
    last_name,
    city,
    country_id,
    payment_date,
    COUNT(*) AS payment_count,
    SUM(amount) AS daily_amount,
    COUNT(DISTINCT staff_id) AS staff_count,
    COUNT(DISTINCT store_id) AS store_count,
    GROUP_CONCAT(DISTINCT staff_id) AS staff_ids,
    GROUP_CONCAT(DISTINCT store_id) AS store_ids
  FROM payment_base
  GROUP BY
    customer_id,
    first_name,
    last_name,
    city,
    country_id,
    payment_date
),
scored_days AS (
  SELECT
    d.*,
    (
      SELECT COALESCE(SUM(p2.amount), 0) / 30.0
      FROM payment_base AS p2
      WHERE p2.customer_id = d.customer_id
        AND p2.payment_date >= date(d.payment_date, '-30 days')
        AND p2.payment_date < d.payment_date
    ) AS avg_daily_amount_prev_30d
  FROM daily_activity AS d
)
SELECT
  customer_id,
  first_name,
  last_name,
  city,
  country_id AS country,
  payment_date,
  payment_count,
  ROUND(daily_amount, 2) AS daily_amount,
  staff_count,
  store_count,
  staff_ids,
  store_ids,
  ROUND(avg_daily_amount_prev_30d, 2) AS avg_daily_amount_prev_30d,
  ROUND(daily_amount - avg_daily_amount_prev_30d, 2) AS deviation_from_30d_norm,
  ROUND(daily_amount / NULLIF(avg_daily_amount_prev_30d, 0), 2) AS deviation_ratio,
  RANK() OVER (
    ORDER BY daily_amount - avg_daily_amount_prev_30d DESC
  ) AS deviation_rank
FROM scored_days
WHERE payment_count >= 3
  AND (staff_count >= 2 OR store_count >= 2)
  AND avg_daily_amount_prev_30d > 0
  AND daily_amount > 2 * avg_daily_amount_prev_30d
ORDER BY
  deviation_rank,
  daily_amount DESC;