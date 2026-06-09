WITH monthly AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cn.c01 AS country_id,
    cn.c02 AS country_name,
    ct.d02 AS city_name,
    date(p.p06, 'start of month') AS month_start,
    SUM(p.p05) AS monthly_amount,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT c.h02) AS distinct_customer_stores_count,
    COUNT(DISTINCT s.j01) AS distinct_customer_employee_stores_count
  FROM pay p
  JOIN cus c
    ON c.h01 = p.p02
  JOIN sto s
    ON s.j01 = c.h02
  JOIN adr a
    ON a.e01 = c.h06
  JOIN cty ct
    ON ct.d01 = a.e05
  JOIN cnt cn
    ON cn.c01 = ct.d03
  WHERE p.p06 IS NOT NULL
  GROUP BY
    c.h01,
    c.h02,
    c.h03,
    c.h04,
    cn.c01,
    cn.c02,
    ct.d02,
    date(p.p06, 'start of month')
),
with_prev AS (
  SELECT
    m.*,
    AVG(monthly_amount) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS avg_prev_3_months,
    AVG(monthly_amount) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS avg_prev_3_months_for_check
  FROM monthly m
),
country_month_ordered AS (
  SELECT
    wp.*,
    ROW_NUMBER() OVER (
      PARTITION BY country_id, month_start
      ORDER BY monthly_amount
    ) AS rn_asc,
    COUNT(*) OVER (
      PARTITION BY country_id, month_start
    ) AS cnt_in_country
  FROM with_prev wp
),
country_month_pcts AS (
  SELECT
    country_id,
    month_start,
    AVG(CASE
      WHEN rn_asc IN (CAST((cnt_in_country + 1) / 2.0 AS INT), CAST((cnt_in_country + 2) / 2.0 AS INT))
      THEN monthly_amount END) AS median_monthly_amount,
    MAX(CASE
      WHEN rn_asc = CAST(0.95 * (cnt_in_country + 1) AS INT)
      THEN monthly_amount
    END) AS p95_monthly_amount
  FROM country_month_ordered
  GROUP BY
    country_id,
    month_start
)
SELECT
  wp.customer_id AS h01,
  wp.first_name AS h03,
  wp.last_name AS h04,
  wp.country_name AS cty_country_name,
  wp.city_name AS city,
  wp.month_start AS month,
  ROUND(wp.monthly_amount, 2) AS month_amount,
  wp.payment_count,
  wp.distinct_staff_count,
  wp.distinct_customer_stores_count AS distinct_h02_count,
  wp.distinct_customer_employee_stores_count AS distinct_j01_count,
  ROUND(wp.avg_prev_3_months, 2) AS avg_prev_3_months,
  ROUND(cmp.median_monthly_amount, 2) AS country_median_month_amount,
  ROUND(cmp.p95_monthly_amount, 2) AS country_p95_month_amount,
  RANK() OVER (
    PARTITION BY wp.country_id, wp.month_start
    ORDER BY wp.monthly_amount DESC
  ) AS country_month_volume_rank
FROM with_prev wp
JOIN country_month_pcts cmp
  ON cmp.country_id = wp.country_id
 AND cmp.month_start = wp.month_start
WHERE wp.avg_prev_3_months_for_check IS NOT NULL
  AND wp.monthly_amount >= 3.0 * wp.avg_prev_3_months_for_check
  AND wp.monthly_amount >= 2.0 * cmp.median_monthly_amount
  AND RANK() OVER (
        PARTITION BY wp.country_id, wp.month_start
        ORDER BY wp.monthly_amount DESC
      ) <= CAST(0.05 * (
        SELECT COUNT(*)
        FROM monthly m2
        WHERE m2.country_id = wp.country_id
          AND m2.month_start = wp.month_start
      ) AS INT) + 1
ORDER BY
  wp.country_name,
  wp.month_start,
  country_month_volume_rank,
  wp.customer_id;