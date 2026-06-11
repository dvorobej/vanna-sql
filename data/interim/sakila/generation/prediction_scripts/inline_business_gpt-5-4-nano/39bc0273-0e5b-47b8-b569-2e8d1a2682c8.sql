WITH payments_monthly AS (
  SELECT
    p.p02 AS customer_id,
    c.h03 AS customer_first_name,
    c.h04 AS customer_last_name,
    c.h02 AS customer_home_store_id,
    co.c02 AS country_name,
    ct.d02 AS city_name,
    p.p03 AS staff_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(p.p01) AS payment_count,
    SUM(p.p05) AS monthly_amount,
    AVG(p.p05) AS avg_check,
    SUM(CASE WHEN strftime('%d', p.p06) = '01' THEN p.p05 ELSE 0 END) AS day_01_amount,
    SUM(CASE WHEN strftime('%d', p.p06) = '02' THEN p.p05 ELSE 0 END) AS day_02_amount,
    SUM(CASE WHEN strftime('%d', p.p06) = '03' THEN p.p05 ELSE 0 END) AS day_03_amount,
    SUM(p.p05) AS total_amount_for_dist
  FROM pay p
  JOIN cus c ON c.h01 = p.p02
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ct ON ct.d01 = a.e05
  JOIN cnt co ON co.c01 = ct.d03
  GROUP BY
    p.p02,
    c.h03,
    c.h04,
    c.h02,
    co.c02,
    ct.d02,
    p.p03,
    date(p.p06, 'start of month')
),
monthly_customer AS (
  SELECT
    customer_id,
    customer_first_name,
    customer_last_name,
    customer_home_store_id,
    country_name,
    city_name,
    month_start,
    SUM(payment_count) AS payment_count,
    SUM(monthly_amount) AS monthly_amount,
    AVG(avg_check) AS avg_check,
    SUM(day_01_amount) AS day_01_amount,
    SUM(day_02_amount) AS day_02_amount,
    SUM(day_03_amount) AS day_03_amount
  FROM payments_monthly
  GROUP BY
    customer_id,
    customer_first_name,
    customer_last_name,
    customer_home_store_id,
    country_name,
    city_name,
    month_start
),
monthly_with_history AS (
  SELECT
    mc.*,
    LAG(mc.monthly_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
    ) AS prev_month_amount,
    AVG(mc.monthly_amount) OVER (
      PARTITION BY mc.country_name
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS country_avg_monthly_amount
  FROM monthly_customer mc
),
anomalous_months AS (
  SELECT
    mwh.*,
    (CASE
      WHEN prev_month_amount IS NULL OR prev_month_amount = 0 THEN NULL
      ELSE (monthly_amount * 1.0 / prev_month_amount)
    END) AS growth_ratio_vs_prev,
    (CASE
      WHEN country_avg_monthly_amount IS NULL OR country_avg_monthly_amount = 0 THEN NULL
      ELSE (monthly_amount * 1.0 / country_avg_monthly_amount)
    END) AS ratio_vs_country_avg
  FROM monthly_with_history mwh
  WHERE
    prev_month_amount IS NOT NULL
    AND prev_month_amount > 0
    AND (
      monthly_amount >= prev_month_amount * 2
      OR (country_avg_monthly_amount IS NOT NULL AND country_avg_monthly_amount > 0 AND monthly_amount >= country_avg_monthly_amount * 1.5)
    )
),
month_staff_share AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id,
    SUM(p.p05) AS staff_amount,
    SUM(SUM(p.p05)) OVER (
      PARTITION BY p.p02, date(p.p06, 'start of month')
    ) AS month_total_amount
  FROM pay p
  GROUP BY
    p.p02, date(p.p06, 'start of month'), p.p03
),
top_staff_in_month AS (
  SELECT
    mss.customer_id,
    mss.month_start,
    mss.staff_id,
    mss.staff_amount,
    ROW_NUMBER() OVER (
      PARTITION BY mss.customer_id, mss.month_start
      ORDER BY mss.staff_amount DESC, mss.staff_id
    ) AS rn
  FROM month_staff_share mss
),
monthly_country_rank AS (
  SELECT
    customer_id,
    month_start,
    DENSE_RANK() OVER (
      PARTITION BY country_name, month_start
      ORDER BY monthly_amount DESC
    ) AS country_month_rank
  FROM anomalous_months
)
SELECT
  am.customer_id,
  am.customer_first_name,
  am.customer_last_name,
  am.customer_home_store_id AS customer_store_id,
  am.country_name AS country,
  am.city_name AS city,
  am.month_start AS month,
  ROUND(am.monthly_amount, 2) AS monthly_amount,
  am.payment_count,
  ROUND(am.avg_check, 2) AS avg_check,
  ROUND(am.day_01_amount, 2) AS day_01_amount,
  ROUND(am.day_02_amount, 2) AS day_02_amount,
  ROUND(am.day_03_amount, 2) AS day_03_amount,
  ROUND(am.growth_ratio_vs_prev, 3) AS growth_ratio_vs_prev_month,
  ROUND(am.ratio_vs_country_avg, 3) AS ratio_vs_country_avg,
  mcr.country_month_rank,
  ts.staff_id AS top_staff_id,
  st.o02 AS top_staff_first_name,
  st.o03 AS top_staff_last_name,
  ROUND(ts.staff_amount, 2) AS top_staff_amount
FROM anomalous_months am
LEFT JOIN monthly_country_rank mcr
  ON mcr.customer_id = am.customer_id
 AND mcr.month_start = am.month_start
LEFT JOIN top_staff_in_month ts
  ON ts.customer_id = am.customer_id
 AND ts.month_start = am.month_start
 AND ts.rn = 1
LEFT JOIN stf st
  ON st.o01 = ts.staff_id
ORDER BY
  am.month_start,
  am.country_name,
  mcr.country_month_rank,
  am.monthly_amount DESC,
  am.customer_id;