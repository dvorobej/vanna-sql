WITH payment_enriched AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    cu.h03 AS first_name,
    cu.h04 AS last_name,
    ci.d02 AS city_name,
    co.c02 AS country_name,
    date(p.p06) AS payment_day,
    p.p05 AS amount,
    p.p03 AS staff_id,
    st.o02 || ' ' || st.o03 AS staff_name,
    st.o07 AS store_id
  FROM pay AS p
  JOIN cus AS cu
    ON cu.h01 = p.p02
  JOIN adr AS ad
    ON ad.e01 = cu.h06
  JOIN cty AS ci
    ON ci.d01 = ad.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
  JOIN stf AS st
    ON st.o01 = p.p03
),
daily_activity AS (
  SELECT
    customer_id,
    first_name,
    last_name,
    city_name,
    country_name,
    payment_day,
    COUNT(payment_id) AS payment_count,
    SUM(amount) AS daily_amount,
    COUNT(DISTINCT staff_id) AS distinct_staff_count,
    COUNT(DISTINCT store_id) AS distinct_store_count,
    GROUP_CONCAT(DISTINCT store_id) AS related_stores,
    GROUP_CONCAT(DISTINCT staff_id || ': ' || staff_name) AS related_staff
  FROM payment_enriched
  GROUP BY
    customer_id,
    first_name,
    last_name,
    city_name,
    country_name,
    payment_day
),
daily_with_norm AS (
  SELECT
    d.*,
    (
      SELECT AVG(d2.daily_amount)
      FROM daily_activity AS d2
      WHERE d2.customer_id = d.customer_id
        AND d2.payment_day >= date(d.payment_day, '-30 day')
        AND d2.payment_day < d.payment_day
    ) AS avg_daily_amount_prev_30d
  FROM daily_activity AS d
),
ranked_days AS (
  SELECT
    *,
    daily_amount - avg_daily_amount_prev_30d AS deviation_from_30d_norm,
    daily_amount / NULLIF(avg_daily_amount_prev_30d, 0) AS ratio_to_30d_norm,
    RANK() OVER (
      PARTITION BY customer_id
      ORDER BY daily_amount - avg_daily_amount_prev_30d DESC
    ) AS deviation_rank
  FROM daily_with_norm
  WHERE avg_daily_amount_prev_30d > 0
)
SELECT
  customer_id,
  first_name,
  last_name,
  city_name,
  country_name,
  payment_day,
  payment_count,
  ROUND(daily_amount, 2) AS daily_amount,
  distinct_store_count,
  related_stores,
  distinct_staff_count,
  related_staff,
  ROUND(avg_daily_amount_prev_30d, 2) AS avg_daily_amount_prev_30d,
  ROUND(deviation_from_30d_norm, 2) AS deviation_from_30d_norm,
  ROUND(ratio_to_30d_norm, 2) AS ratio_to_30d_norm,
  deviation_rank
FROM ranked_days
WHERE payment_count >= 3
  AND (
    distinct_staff_count > 1
    OR distinct_store_count > 1
  )
  AND daily_amount > 2 * avg_daily_amount_prev_30d
ORDER BY
  deviation_rank,
  deviation_from_30d_norm DESC,
  customer_id,
  payment_day;