SELECT DISTINCT
    scmp.store_id,
    scmp.country_name,
    scmp.month_start,
    scmp.customer_id
  FROM store_country_month_percentiles AS scmp
  WHERE scmp.pr >= 0.95
),
qualifying AS (
  SELECT
    cwh.*,
    sm95.customer_id AS in_top_95_flag
  FROM customer_with_history AS cwh
  JOIN top_store_country_95 AS sm95
    ON sm95.customer_id = cwh.customer_id
   AND sm95.store_id = cwh.store_id
   AND sm95.country_name = cwh.country_name
   AND sm95.month_start = cwh.month_start
  WHERE
    cwh.customer_prev_avg_month_sum IS NOT NULL
    AND cwh.month_payment_sum > 3.0 * cwh.customer_prev_avg_month_sum
),
overdue_share AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(
      CASE
        WHEN r.q05 IS NOT NULL AND r.q02 IS NOT NULL AND r.q05 > r.q02 THEN 1
        WHEN r.q05 IS NOT NULL THEN 1
        ELSE 0
      END
    ) * 1.0 / COUNT(p.p01) AS overdue_return_payment_share
  FROM pay AS p
  JOIN ren AS r
    ON r.q01 = p.p04
  WHERE p.p06 IS NOT NULL
  GROUP BY p.p02, date(p.p06, 'start of month')
),
monthly_store_rank AS (
  SELECT
    mc.customer_id,
    mc.month_start,
    RANK() OVER (
      PARTITION BY mc.store_id, mc.country_name, mc.month_start
      ORDER BY mc.month_payment_sum DESC
    ) AS customer_month_store_rank
  FROM monthly_customer AS mc
)
SELECT
  q.customer_id AS h01,
  q.first_name AS h03,
  q.last_name AS h04,
  q.country_name AS c02,
  q.city_name AS d02,
  q.store_id AS j01,
  strftime('%Y-%m', q.month_start) AS month,
  ROUND(q.month_payment_sum, 2) AS month_payment_sum,
  q.payment_count AS payment_count,
  q.distinct_staff_count AS distinct_staff_count,
  ROUND(COALESCE(os.overdue_return_payment_share, 0.0), 4) AS overdue_return_payment_share,
  msr.customer_month_store_rank AS customer_month_store_rank
FROM qualifying AS q
LEFT JOIN overdue_share AS os
  ON os.customer_id = q.customer_id
 AND os.month_start = q.month_start
LEFT JOIN monthly_store_rank AS msr
  ON msr.customer_id = q.customer_id
 AND msr.month_start = q.month_start
ORDER BY
  q.month_start,
  q.store_id,
  q.country_name,
  customer_month_store_rank,
  q.customer_id;