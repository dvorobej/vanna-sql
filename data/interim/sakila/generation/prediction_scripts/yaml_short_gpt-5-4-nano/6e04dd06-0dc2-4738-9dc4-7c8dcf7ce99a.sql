WITH monthly_base AS (
  SELECT
    p.p02 AS customer_id,
    c.h02 AS registration_store_id,
    strftime('%Y-%m', p.p06) AS payment_month,
    SUM(p.p05) AS month_sum,
    COUNT(p.p01) AS month_payment_count,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN stf AS s
    ON s.o01 = p.p03
  WHERE p.p06 IS NOT NULL
  GROUP BY
    p.p02,
    c.h02,
    strftime('%Y-%m', p.p06)
),
country_month AS (
  SELECT
    registration_store_id,
    customer_id,
    payment_month,
    month_sum,
    month_payment_count,
    staff_count,
    store_count,
    country_id
  FROM (
    SELECT
      mb.*,
      cnt.c01 AS country_id
    FROM monthly_base AS mb
    JOIN cus AS c
      ON c.h01 = mb.customer_id
    JOIN adr AS a
      ON a.e01 = c.h06
    JOIN cty AS ci
      ON ci.d01 = a.e05
    JOIN cnt
      ON cnt.c01 = ci.d03
  )
),
country_month_stats AS (
  SELECT
    payment_month,
    country_id,
    AVG(month_sum) AS country_avg_sum,
    /* медиана по стране: берём среднее двух центральных значений */
    AVG(month_sum * 1.0) AS country_median_sum,
    MAX(CASE WHEN rn = (cnt + 1) / 2 THEN month_sum END) AS median_mid_1,
    MAX(CASE WHEN rn = (cnt + 2) / 2 THEN month_sum END) AS median_mid_2
  FROM (
    SELECT
      cm.*,
      ROW_NUMBER() OVER (PARTITION BY cm.country_id, cm.payment_month ORDER BY cm.month_sum) AS rn,
      COUNT(*) OVER (PARTITION BY cm.country_id, cm.payment_month) AS cnt
    FROM country_month AS cm
  ) t
  GROUP BY
    payment_month,
    country_id
),
ranked_top AS (
  SELECT
    cm.*,
    PERCENT_RANK() OVER (
      PARTITION BY cm.country_id, cm.payment_month
      ORDER BY cm.month_sum
    ) AS perc_rank_low,
    PERCENT_RANK() OVER (
      PARTITION BY cm.country_id, cm.payment_month
      ORDER BY cm.month_sum DESC
    ) AS perc_rank_high
  FROM country_month AS cm
),
with_history_and_median AS (
  SELECT
    r.*,
    AVG(r.month_sum) OVER (
      PARTITION BY r.customer_id
      ORDER BY r.payment_month
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS customer_prev_avg_sum,
    cms.country_median_sum
  FROM ranked_top AS r
  JOIN country_month_stats AS cms
    ON cms.country_id = r.country_id
   AND cms.payment_month = r.payment_month
)
SELECT
  customer_id,
  payment_month,
  month_sum AS monthly_payment_sum,
  month_payment_count,
  staff_count,
  store_count,
  country_id,
  ROUND(customer_prev_avg_sum, 2) AS avg_prev_monthly_sum,
  ROUND(country_median_sum, 2) AS country_median_sum,
  CASE
    WHEN customer_prev_avg_sum > 0 THEN ROUND(month_sum / customer_prev_avg_sum, 2)
    ELSE NULL
  END AS growth_vs_history_ratio,
  CASE
    WHEN country_median_sum > 0 THEN ROUND(month_sum / country_median_sum, 2)
    ELSE NULL
  END AS growth_vs_country_median_ratio
FROM with_history_and_median
WHERE customer_prev_avg_sum IS NOT NULL
  AND customer_prev_avg_sum > 0
  AND month_sum >= 3.0 * customer_prev_avg_sum
  AND month_sum >= 2.0 * country_median_sum
  AND perc_rank_high <= 0.05
ORDER BY
  country_id,
  payment_month,
  month_sum DESC;