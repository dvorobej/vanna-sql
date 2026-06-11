WITH monthly_client AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS customer_first_name,
    c.h04 AS customer_last_name,
    co.c02 AS country_name,
    strftime('%Y-%m', p.p06) AS payment_month,
    COUNT(p.p01) AS payment_count,
    SUM(p.p05) AS month_payment_sum,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay p
  JOIN cus c
    ON c.h01 = p.p02
  JOIN stf s
    ON s.o01 = p.p03
  JOIN adr a
    ON a.e01 = c.h06
  JOIN cty ci
    ON ci.d01 = a.e05
  JOIN cnt co
    ON co.c01 = ci.d03
  WHERE p.p06 IS NOT NULL
  GROUP BY
    c.h01,
    c.h03,
    c.h04,
    co.c02,
    strftime('%Y-%m', p.p06)
),
with_history AS (
  SELECT
    mc.*,
    (
      SELECT AVG(mc2.month_payment_sum)
      FROM monthly_client mc2
      WHERE mc2.customer_id = mc.customer_id
        AND mc2.payment_month >= strftime('%Y-%m', date(mc.payment_month || '-01', '-3 months'))
        AND mc2.payment_month <  strftime('%Y-%m', date(mc.payment_month || '-01', '-0 months'))
        AND mc2.payment_month < mc.payment_month
        AND mc2.payment_month >= strftime('%Y-%m', date(mc.payment_month || '-01', '-3 months'))
      ORDER BY mc2.payment_month
    ) AS avg_prev_3_months_sum
  FROM monthly_client mc
),
country_months AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY country_name, payment_month
      ORDER BY month_payment_sum
    ) AS rn_asc,
    COUNT(*) OVER (
      PARTITION BY country_name, payment_month
    ) AS cnt_in_month
  FROM monthly_client
),
median_country_month AS (
  SELECT
    country_name,
    payment_month,
    AVG(month_payment_sum) AS median_country_month_sum
  FROM (
    SELECT
      country_name,
      payment_month,
      month_payment_sum,
      rn_asc,
      cnt_in_month
    FROM country_months
  ) x
  WHERE rn_asc IN (
    CAST((cnt_in_month + 1) / 2 AS INTEGER),
    CAST((cnt_in_month + 2) / 2 AS INTEGER)
  )
  GROUP BY country_name, payment_month
),
rank_country_month AS (
  SELECT
    cm.*,
    PERCENT_RANK() OVER (
      PARTITION BY country_name, payment_month
      ORDER BY month_payment_sum
    ) AS pct_rank_asc
  FROM monthly_client cm
),
combined AS (
  SELECT
    r.customer_id,
    r.customer_first_name,
    r.customer_last_name,
    r.country_name,
    r.payment_month,
    r.payment_count,
    ROUND(r.month_payment_sum, 2) AS month_payment_sum,
    r.staff_count,
    r.store_count,
    r.avg_prev_3_months_sum,
    mcm.median_country_month_sum,
    RANK() OVER (
      PARTITION BY r.country_name, r.payment_month
      ORDER BY r.month_payment_sum DESC
    ) AS country_month_rank_desc,
    r.pct_rank_asc
  FROM with_history r
  JOIN median_country_month mcm
    ON mcm.country_name = r.country_name
   AND mcm.payment_month = r.payment_month
  JOIN rank_country_month r2
    ON r2.customer_id = r.customer_id
   AND r2.payment_month = r.payment_month
   AND r2.country_name = r.country_name
)
SELECT
  customer_id,
  customer_first_name || ' ' || customer_last_name AS customer_name,
  country_name,
  payment_month,
  payment_count,
  month_payment_sum,
  staff_count,
  store_count,
  ROUND(avg_prev_3_months_sum, 2) AS avg_prev_3_months_sum,
  ROUND(median_country_month_sum, 2) AS median_country_month_sum,
  ROUND(month_payment_sum / NULLIF(avg_prev_3_months_sum, 0), 3) AS growth_vs_history_factor,
  ROUND(month_payment_sum / NULLIF(median_country_month_sum, 0), 3) AS ratio_vs_country_median,
  country_month_rank_desc
FROM combined
WHERE avg_prev_3_months_sum IS NOT NULL
  AND avg_prev_3_months_sum > 0
  AND month_payment_sum >= 3.0 * avg_prev_3_months_sum
  AND month_payment_sum >= 2.0 * median_country_month_sum
  AND pct_rank_asc >= 0.95
ORDER BY
  country_name,
  payment_month,
  month_payment_sum DESC,
  customer_id;