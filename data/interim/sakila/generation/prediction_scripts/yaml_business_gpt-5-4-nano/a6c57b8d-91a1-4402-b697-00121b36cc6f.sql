WITH monthly_customer_payments AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS payment_month,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS month_total_amount,
    MAX(p.p05) AS max_single_payment
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06)
),
monthly_with_personal_baseline AS (
  SELECT
    mcp.*,
    AVG(mcp.month_total_amount) OVER (
      PARTITION BY mcp.customer_id
      ORDER BY mcp.payment_month
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS personal_avg_prev_months_amount,
    AVG(mcp.payment_count * 1.0) OVER (
      PARTITION BY mcp.customer_id
      ORDER BY mcp.payment_month
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS personal_avg_prev_months_count
  FROM monthly_customer_payments AS mcp
),
country_month_percentiles AS (
  SELECT
    mcp.payment_month,
    c.h01 AS customer_id,
    c.h02 AS country_id,
    COUNT(*) OVER (PARTITION BY strftime('%Y-%m', (SELECT MIN(p2.p06) FROM pay p2 WHERE p2.p02 = mcp.customer_id)) ) AS dummy
  FROM cus c
  JOIN monthly_customer_payments mcp
    ON mcp.customer_id = c.h01
),
customer_country_city AS (
  SELECT
    c.h01 AS customer_id,
    cnt.c02 AS country_name,
    ci.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt ON cnt.c01 = ci.d03
),
country_month_top10 AS (
  SELECT
    mcp.payment_month,
    mcp.customer_id,
    RANK() OVER (
      PARTITION BY mcp.payment_month
      ORDER BY mcp.month_total_amount DESC
    ) AS rank_in_country_month,
    COUNT(*) OVER (
      PARTITION BY mcp.payment_month
    ) AS customers_in_country_month,
    PERCENT_RANK() OVER (
      PARTITION BY mcp.payment_month
      ORDER BY mcp.month_total_amount DESC
    ) AS percent_rank_in_country_month
  FROM monthly_customer_payments AS mcp
),
staff_top_month AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS payment_month,
    p.p03 AS top_staff_id
  FROM pay AS p
  JOIN (
    SELECT
      p2.p02 AS customer_id,
      strftime('%Y-%m', p2.p06) AS payment_month,
      p2.p03 AS staff_id,
      SUM(CAST(p2.p05 AS REAL)) AS staff_month_amount
    FROM pay AS p2
    WHERE p2.p06 >= '2005-01-01'
      AND p2.p06 < '2006-01-01'
    GROUP BY
      p2.p02,
      strftime('%Y-%m', p2.p06),
      p2.p03
  ) AS s
    ON s.customer_id = p.p02
   AND s.payment_month = strftime('%Y-%m', p.p06)
   AND s.staff_id = p.p03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06),
    p.p03
),
staff_top_month_ranked AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS payment_month,
    p.p03 AS staff_id,
    SUM(CAST(p.p05 AS REAL)) AS staff_month_total_amount,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, strftime('%Y-%m', p.p06)
      ORDER BY SUM(CAST(p.p05 AS REAL)) DESC, p.p03
    ) AS rn
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06),
    p.p03
),
staff_month_top1 AS (
  SELECT
    customer_id,
    payment_month,
    staff_id AS top_staff_id
  FROM staff_top_month_ranked
  WHERE rn = 1
)
SELECT
  c.h01 AS customer_id,
  c.h03 AS customer_first_name,
  c.h04 AS customer_last_name,
  ccn.country_name,
  ccn.city_name,
  mcp.payment_month,
  ROUND(mcp.month_total_amount, 2) AS month_total_amount,
  mcp.payment_count,
  ROUND(mcp.personal_avg_prev_months_amount, 2) AS personal_avg_prev_months_amount,
  ROUND(mcp.month_total_amount / NULLIF(mcp.personal_avg_prev_months_amount, 0), 2) AS amount_deviation_multiplier,
  ctm.rank_in_country_month,
  ctm.customers_in_country_month,
  st.o02 AS top_staff_first_name,
  st.o03 AS top_staff_last_name
FROM monthly_with_personal_baseline AS mcp
JOIN cus AS c
  ON c.h01 = mcp.customer_id
JOIN customer_country_city AS ccn
  ON ccn.customer_id = c.h01
JOIN country_month_top10 AS ctm
  ON ctm.customer_id = mcp.customer_id
 AND ctm.payment_month = mcp.payment_month
JOIN staff_month_top1 AS sm
  ON sm.customer_id = mcp.customer_id
 AND sm.payment_month = mcp.payment_month
JOIN stf AS st
  ON st.o01 = sm.top_staff_id
WHERE
  mcp.personal_avg_prev_months_amount IS NOT NULL
  AND mcp.payment_count > 0
  AND mcp.month_total_amount >= mcp.personal_avg_prev_months_amount * 1.50
  AND ctm.percent_rank_in_country_month <= 0.10
ORDER BY
  mcp.payment_month,
  month_total_amount DESC,
  customer_id;