WITH RECURSIVE
payment_bounds AS (
  SELECT
    date(MIN(p06), 'start of month') AS min_month,
    date(MAX(p06), 'start of month') AS max_month
  FROM pay
),
months(month_start) AS (
  SELECT min_month
  FROM payment_bounds
  WHERE min_month IS NOT NULL
  UNION ALL
  SELECT date(month_start, '+1 month')
  FROM months, payment_bounds
  WHERE month_start < max_month
),
customer_base AS (
  SELECT
    cus.h01 AS customer_id,
    cus.h03 || ' ' || cus.h04 AS customer_name,
    cus.h02 AS home_store_id,
    cnt.c01 AS country_id,
    cnt.c02 AS country_name
  FROM cus
  JOIN adr ON adr.e01 = cus.h06
  JOIN cty ON cty.d01 = adr.e05
  JOIN cnt ON cnt.c01 = cty.d03
),
monthly_payments AS (
  SELECT
    pay.p02 AS customer_id,
    date(pay.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(pay.p05) AS payment_amount,
    SUM(CASE WHEN stf.o07 <> cus.h02 THEN 1 ELSE 0 END) AS off_home_store_payment_count,
    COUNT(DISTINCT pay.p03) AS distinct_staff_count
  FROM pay
  JOIN cus ON cus.h01 = pay.p02
  JOIN stf ON stf.o01 = pay.p03
  GROUP BY
    pay.p02,
    date(pay.p06, 'start of month')
),
customer_monthly AS (
  SELECT
    cb.customer_id,
    cb.customer_name,
    cb.home_store_id,
    cb.country_id,
    cb.country_name,
    m.month_start,
    COALESCE(mp.payment_count, 0) AS payment_count,
    COALESCE(mp.payment_amount, 0.0) AS payment_amount,
    COALESCE(mp.off_home_store_payment_count, 0) AS off_home_store_payment_count,
    COALESCE(mp.distinct_staff_count, 0) AS distinct_staff_count
  FROM customer_base AS cb
  CROSS JOIN months AS m
  LEFT JOIN monthly_payments AS mp
    ON mp.customer_id = cb.customer_id
   AND mp.month_start = m.month_start
),
customer_rolling AS (
  SELECT
    cm.*,
    AVG(cm.payment_count) OVER (
      PARTITION BY cm.customer_id
      ORDER BY cm.month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS prev_2_month_avg_payment_count,
    AVG(cm.payment_amount) OVER (
      PARTITION BY cm.customer_id
      ORDER BY cm.month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS prev_2_month_avg_payment_amount,
    COUNT(*) OVER (
      PARTITION BY cm.customer_id
      ORDER BY cm.month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS prev_2_months_available
  FROM customer_monthly AS cm
),
country_distribution AS (
  SELECT
    cm.*,
    AVG(cm.payment_count) OVER (
      PARTITION BY cm.country_id, cm.month_start
    ) AS country_avg_payment_count,
    AVG(cm.payment_amount) OVER (
      PARTITION BY cm.country_id, cm.month_start
    ) AS country_avg_payment_amount,
    COUNT(*) OVER (
      PARTITION BY cm.country_id, cm.month_start
    ) AS country_customer_count,
    ROW_NUMBER() OVER (
      PARTITION BY cm.country_id, cm.month_start
      ORDER BY cm.payment_amount
    ) AS amount_asc_row_num
  FROM customer_monthly AS cm
),
country_percentile_positions AS (
  SELECT
    cd.*,
    1.0 + (cd.country_customer_count - 1) * 0.95 AS p95_position
  FROM country_distribution AS cd
),
country_percentile_bounds AS (
  SELECT
    cpp.*,
    CAST(cpp.p95_position AS INTEGER) AS p95_low_row_num,
    CASE
      WHEN cpp.p95_position = CAST(cpp.p95_position AS INTEGER)
      THEN CAST(cpp.p95_position AS INTEGER)
      ELSE CAST(cpp.p95_position AS INTEGER) + 1
    END AS p95_high_row_num
  FROM country_percentile_positions AS cpp
),
country_stats AS (
  SELECT
    country_id,
    country_name,
    month_start,
    MAX(country_customer_count) AS country_customer_count,
    MAX(country_avg_payment_count) AS country_avg_payment_count,
    MAX(country_avg_payment_amount) AS country_avg_payment_amount,
    CASE
      WHEN MAX(p95_low_row_num) = MAX(p95_high_row_num) THEN
        MAX(CASE WHEN amount_asc_row_num = p95_low_row_num THEN payment_amount END)
      ELSE
        MAX(CASE WHEN amount_asc_row_num = p95_low_row_num THEN payment_amount END)
          * (MAX(p95_high_row_num) - MAX(p95_position))
        +
        MAX(CASE WHEN amount_asc_row_num = p95_high_row_num THEN payment_amount END)
          * (MAX(p95_position) - MAX(p95_low_row_num))
    END AS country_payment_amount_p95
  FROM country_percentile_bounds
  GROUP BY
    country_id,
    country_name,
    month_start
),
ranked_customer_monthly AS (
  SELECT
    cr.*,
    RANK() OVER (
      PARTITION BY cr.country_id, cr.month_start
      ORDER BY cr.payment_amount DESC
    ) AS country_month_payment_amount_rank
  FROM customer_rolling AS cr
)
SELECT
  rcm.customer_id,
  rcm.customer_name,
  rcm.country_id,
  rcm.country_name,
  strftime('%Y-%m', rcm.month_start) AS payment_month,
  rcm.payment_count,
  ROUND(rcm.payment_amount, 2) AS payment_amount,
  ROUND(rcm.prev_2_month_avg_payment_count, 2) AS prev_2_month_avg_payment_count,
  ROUND(rcm.prev_2_month_avg_payment_amount, 2) AS prev_2_month_avg_payment_amount,
  ROUND(cs.country_avg_payment_count, 2) AS country_avg_payment_count,
  ROUND(cs.country_avg_payment_amount, 2) AS country_avg_payment_amount,
  ROUND(cs.country_payment_amount_p95, 2) AS country_payment_amount_p95,
  ROUND(1.0 * rcm.off_home_store_payment_count / NULLIF(rcm.payment_count, 0), 4) AS off_home_store_payment_share,
  rcm.distinct_staff_count,
  rcm.country_month_payment_amount_rank
FROM ranked_customer_monthly AS rcm
JOIN country_stats AS cs
  ON cs.country_id = rcm.country_id
 AND cs.month_start = rcm.month_start
WHERE rcm.payment_count > 0
  AND rcm.prev_2_months_available = 2
  AND rcm.prev_2_month_avg_payment_amount > 0
  AND rcm.payment_amount >= 3.0 * rcm.prev_2_month_avg_payment_amount
  AND rcm.payment_amount > cs.country_payment_amount_p95
ORDER BY
  rcm.month_start,
  rcm.country_name,
  rcm.payment_amount DESC,
  rcm.customer_id;