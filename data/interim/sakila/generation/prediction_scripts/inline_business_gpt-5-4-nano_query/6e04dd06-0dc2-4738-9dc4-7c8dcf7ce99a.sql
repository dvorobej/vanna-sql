SELECT AVG(pm2.payment_sum)
      FROM pm pm2
      WHERE pm2.customer_id = pm.customer_id
        AND pm2.month_start < pm.month_start
        AND pm2.month_start >= DATE(pm.month_start, '-3 months')
    ) AS avg_prev_3_months_sum
  FROM pm
),
country_month_sums AS (
  SELECT
    country_id,
    month_start,
    payment_sum,
    DENSE_RANK() OVER (
      PARTITION BY country_id, month_start
      ORDER BY payment_sum DESC
    ) AS country_payment_sum_rank_desc,
    COUNT(*) OVER (PARTITION BY country_id, month_start) AS country_cnt
  FROM pm
),
median_by_country_month AS (
  SELECT
    country_id,
    month_start,
    AVG(payment_sum) AS median_payment_sum
  FROM (
    SELECT
      cms.*,
      ROW_NUMBER() OVER (PARTITION BY country_id, month_start ORDER BY payment_sum) AS rn_asc
    FROM country_month_sums cms
  ) x
  WHERE rn_asc IN (
    CAST((country_cnt + 1) / 2 AS INTEGER),
    CAST((country_cnt + 2) / 2 AS INTEGER)
  )
  GROUP BY country_id, month_start
),
country_percentile_top5 AS (
  SELECT
    country_id,
    month_start,
    payment_sum,
    customer_id,
    country_cnt,
    CEIL(0.05 * country_cnt) AS top5_threshold_count
  FROM (
    SELECT
      pm.*,
      COUNT(*) OVER (PARTITION BY country_id, month_start) AS country_cnt,
      ROW_NUMBER() OVER (
        PARTITION BY country_id, month_start
        ORDER BY payment_sum DESC, customer_id
      ) AS rn_desc
    FROM pm
  ) y
  WHERE rn_desc <= CEIL(0.05 * country_cnt)
)
SELECT
  wp.customer_id,
  wp.customer_first_name,
  wp.customer_last_name,
  wp.country_name,
  wp.month_start AS month,
  ROUND(wp.payment_sum, 2) AS monthly_payment_sum,
  wp.payment_count,
  wp.distinct_staff_count,
  wp.distinct_store_count,
  ROUND(wp.avg_prev_3_months_sum, 2) AS avg_prev_3_months_sum,
  ROUND(
    CASE
      WHEN wp.avg_prev_3_months_sum IS NULL OR wp.avg_prev_3_months_sum = 0 THEN NULL
      ELSE wp.payment_sum / wp.avg_prev_3_months_sum
    END,
    3
  ) AS sum_vs_own_history_ratio,
  ROUND(mcm.median_payment_sum, 2) AS country_month_median_sum,
  ROUND(
    CASE
      WHEN mcm.median_payment_sum IS NULL OR mcm.median_payment_sum = 0 THEN NULL
      ELSE wp.payment_sum / mcm.median_payment_sum
    END,
    3
  ) AS sum_vs_country_median_ratio,
  RANK() OVER (
    PARTITION BY wp.country_id, wp.month_start
    ORDER BY wp.payment_sum DESC
  ) AS country_month_rank,
  ROUND(wp.payment_sum, 2) AS risk_amount_for_ranking
FROM with_prev wp
JOIN median_by_country_month mcm
  ON mcm.country_id = wp.country_id
 AND mcm.month_start = wp.month_start
JOIN country_percentile_top5 tp
  ON tp.customer_id = wp.customer_id
 AND tp.country_id = wp.country_id
 AND tp.month_start = wp.month_start
WHERE
  wp.avg_prev_3_months_sum IS NOT NULL
  AND wp.avg_prev_3_months_sum > 0
  AND wp.payment_sum >= 3.0 * wp.avg_prev_3_months_sum
  AND wp.payment_sum >= 2.0 * mcm.median_payment_sum
ORDER BY
  wp.country_name,
  month,
  monthly_payment_sum DESC,
  wp.customer_id;