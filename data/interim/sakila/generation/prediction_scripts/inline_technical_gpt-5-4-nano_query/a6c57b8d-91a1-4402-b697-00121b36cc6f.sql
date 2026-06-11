WITH payments_2005 AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p05 AS payment_amount,
    p.p06 AS payment_ts,
    date(p.p06, 'start of month') AS month_start
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
),
customer_monthly AS (
  SELECT
    p.customer_id,
    p.month_start,
    COUNT(*) AS payment_count,
    SUM(p.payment_amount) AS monthly_amount
  FROM payments_2005 AS p
  GROUP BY p.customer_id, p.month_start
),
customer_monthly_with_prev AS (
  SELECT
    cm.*,
    AVG(cm.monthly_amount) OVER (
      PARTITION BY cm.customer_id
    ) AS avg_monthly_amount_2005
  FROM customer_monthly AS cm
),
country_month_rank AS (
  SELECT
    cmw.*,
    RANK() OVER (
      PARTITION BY cmw.month_start, cmw.customer_id
      ORDER BY cmw.monthly_amount
    ) AS dummy_rank
  FROM customer_monthly_with_prev AS cmw
),
country_months AS (
  SELECT
    cmw.*,
    PERCENT_RANK() OVER (
      PARTITION BY cmw.month_start, 
                   (SELECT c.h02 FROM cus c WHERE c.h01 = cmw.customer_id)
      ORDER BY cmw.monthly_amount
    ) AS country_month_percent_rank
  FROM customer_monthly_with_prev AS cmw
  -- заменим на корректный join к стране ниже
),
country_monthly_ranked AS (
  SELECT
    cmw.customer_id,
    cmw.month_start,
    cmw.payment_count,
    cmw.monthly_amount,
    cmw.avg_monthly_amount_2005,
    PERCENT_RANK() OVER (
      PARTITION BY c.country_id, cmw.month_start
      ORDER BY cmw.monthly_amount
    ) AS country_month_percent_rank
  FROM customer_monthly_with_prev AS cmw
  JOIN (
    SELECT
      cus.h01 AS customer_id,
      cnt.c01 AS country_id
    FROM cus
    JOIN adr ON adr.e01 = cus.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
  ) AS c
    ON c.customer_id = cmw.customer_id
),
suspicious_months AS (
  SELECT
    cmr.*
  FROM country_monthly_ranked AS cmr
  WHERE cmr.avg_monthly_amount_2005 IS NOT NULL
    AND cmr.avg_monthly_amount_2005 > 0
    AND cmr.monthly_amount > 2.0 * cmr.avg_monthly_amount_2005
    AND cmr.country_month_percent_rank >= 0.90
),
top_staff_in_month AS (
  SELECT
    p.customer_id,
    date(p.payment_ts, 'start of month') AS month_start,
    p.staff_id,
    SUM(p.payment_amount) AS staff_month_amount,
    ROW_NUMBER() OVER (
      PARTITION BY p.customer_id, date(p.payment_ts, 'start of month')
      ORDER BY SUM(p.payment_amount) DESC, p.staff_id
    ) AS rn
  FROM payments_2005 AS p
  GROUP BY
    p.customer_id,
    date(p.payment_ts, 'start of month'),
    p.staff_id
)
SELECT
  sm.customer_id,
  co.c02 AS country,
  ct.d02 AS city,
  strftime('%Y-%m', sm.month_start) AS month,
  ROUND(sm.monthly_amount, 2) AS monthly_amount,
  sm.payment_count,
  ROUND(sm.monthly_amount - sm.avg_monthly_amount_2005, 2) AS deviation_from_personal_avg,
  RANK() OVER (
    PARTITION BY ctry.country_id, sm.month_start
    ORDER BY sm.monthly_amount DESC
  ) AS country_customer_rank,
  stf.o01 AS top_staff_id,
  stf.o02 || ' ' || stf.o03 AS top_staff_name
FROM suspicious_months AS sm
JOIN cus AS cusx
  ON cusx.h01 = sm.customer_id
JOIN adr AS a
  ON a.e01 = cusx.h06
JOIN cty AS ct
  ON ct.d01 = a.e05
JOIN cnt AS co
  ON co.c01 = ct.d03
LEFT JOIN (
  SELECT
    customers.customer_id,
    customers.country_id
  FROM (
    SELECT
      cus.h01 AS customer_id,
      cnt.c01 AS country_id
    FROM cus
    JOIN adr ON adr.e01 = cus.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
  ) AS customers
) AS ctry
  ON ctry.customer_id = sm.customer_id
LEFT JOIN top_staff_in_month AS tsim
  ON tsim.customer_id = sm.customer_id
 AND tsim.month_start = sm.month_start
 AND tsim.rn = 1
LEFT JOIN stf
  ON stf.o01 = tsim.staff_id
ORDER BY
  sm.month_start,
  co.c02,
  country_customer_rank,
  sm.customer_id;