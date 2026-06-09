SELECT *
  FROM country_month_ranked
  WHERE pr_country_month >= 0.90
),
selected_months AS (
  SELECT
    customer_id,
    month_start,
    month_amount,
    month_payment_count,
    (month_amount / NULLIF(personal_avg_month_amount, 0)) AS personal_vs_avg_ratio,
    country_name,
    city_name
  FROM country_top_10pct
  WHERE personal_vs_avg_ratio > 2.0
),
staff_top_by_month AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id,
    SUM(p.p05) AS staff_month_amount,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, date(p.p06, 'start of month')
      ORDER BY SUM(p.p05) DESC
    ) AS rn
  FROM pay p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY p.p02, date(p.p06, 'start of month'), p.p03
)
SELECT
  sm.customer_id AS h01,
  sm.country_name,
  sm.city_name,
  sm.month_start AS month,
  ROUND(sm.month_amount, 2) AS month_amount,
  sm.month_payment_count AS month_payment_count,
  ROUND(sm.month_amount - sm.personal_avg_month_amount, 2) AS deviation_from_personal_avg,
  RANK() OVER (
    PARTITION BY sm.country_name, sm.month_start
    ORDER BY sm.month_amount DESC
  ) AS customer_country_month_rank,
  stf_top.staff_id AS top_staff_id,
  stf.o01 AS staff_original_id,
  sm.personal_vs_avg_ratio
FROM selected_months sm
JOIN (
  SELECT customer_id, month_start, staff_id
  FROM staff_top_by_month
  WHERE rn = 1
) stf_top
  ON stf_top.customer_id = sm.customer_id
 AND stf_top.month_start = sm.month_start
LEFT JOIN stf stf
  ON stf.o01 = stf_top.staff_id
ORDER BY
  sm.country_name,
  sm.month_start,
  sm.month_amount DESC,
  sm.customer_id;