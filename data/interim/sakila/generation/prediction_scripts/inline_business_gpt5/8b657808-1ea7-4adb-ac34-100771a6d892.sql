WITH monthly_profile AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cnt.c01 AS country_id,
    cnt.c02 AS country,
    cty.d02 AS city,
    strftime('%Y-%m', p.p06) AS payment_month,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS monthly_amount,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT s.o07) AS distinct_store_count
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty
    ON cty.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = cty.d03
  JOIN stf AS s
    ON s.o01 = p.p03
  GROUP BY
    c.h01,
    c.h03,
    c.h04,
    cnt.c01,
    cnt.c02,
    cty.d02,
    strftime('%Y-%m', p.p06)
),
monthly_with_history AS (
  SELECT
    mp.*,
    AVG(mp.monthly_amount) OVER (
      PARTITION BY mp.customer_id
      ORDER BY mp.payment_month
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS avg_prev_3_months_amount
  FROM monthly_profile AS mp
),
monthly_with_country AS (
  SELECT
    mwh.*,
    AVG(mwh.monthly_amount) OVER (
      PARTITION BY mwh.country_id, mwh.payment_month
    ) AS country_avg_monthly_amount
  FROM monthly_with_history AS mwh
)
SELECT
  customer_id,
  first_name,
  last_name,
  country,
  city,
  payment_month,
  payment_count,
  ROUND(monthly_amount, 2) AS monthly_amount,
  distinct_staff_count,
  distinct_store_count,
  ROUND(avg_prev_3_months_amount, 2) AS avg_prev_3_months_amount,
  ROUND(country_avg_monthly_amount, 2) AS country_avg_monthly_amount,
  ROUND(monthly_amount / avg_prev_3_months_amount, 2) AS ratio_to_prev_3_months,
  ROUND(monthly_amount / country_avg_monthly_amount, 2) AS ratio_to_country_avg
FROM monthly_with_country
WHERE avg_prev_3_months_amount IS NOT NULL
  AND avg_prev_3_months_amount > 0
  AND country_avg_monthly_amount > 0
  AND monthly_amount >= avg_prev_3_months_amount * 2
  AND monthly_amount >= country_avg_monthly_amount * 2
  AND payment_count >= 3
  AND distinct_staff_count > 1
ORDER BY
  payment_month,
  monthly_amount DESC,
  customer_id;