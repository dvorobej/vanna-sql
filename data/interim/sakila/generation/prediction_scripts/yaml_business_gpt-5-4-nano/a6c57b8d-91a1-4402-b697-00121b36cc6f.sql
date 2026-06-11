WITH monthly_customer_payments AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS payment_month,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS month_amount
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06)
),
monthly_with_personal_avg AS (
  SELECT
    mcp.*,
    AVG(mcp.month_amount) OVER (
      PARTITION BY mcp.customer_id
      ORDER BY mcp.payment_month
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS personal_avg_prev_months
  FROM monthly_customer_payments AS mcp
),
country_month_ranked AS (
  SELECT
    mwpa.*,
    RANK() OVER (
      PARTITION BY mwpa.payment_month, mwpa.customer_id
      ORDER BY mwpa.month_amount DESC
    ) AS dummy
  FROM monthly_with_personal_avg AS mwpa
),
country_month_stats AS (
  SELECT
    mwpa.*,
    PERCENT_RANK() OVER (
      PARTITION BY mwpa.payment_month, c.h01
      ORDER BY mwpa.month_amount DESC
    ) AS pr
  FROM monthly_with_personal_avg AS mwpa
  JOIN cus AS c
    ON c.h01 = mwpa.customer_id
),
top10_country_month AS (
  SELECT
    cs.*
  FROM country_month_stats cs
  WHERE cs.personal_avg_prev_months IS NOT NULL
    AND cs.month_amount >= cs.personal_avg_prev_months * 3
    AND cs.pr <= 0.1
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS customer_first_name,
    c.h04 AS customer_last_name,
    cnt.c02 AS country_name,
    cty.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS cty
    ON cty.d01 = a.e05
  JOIN cnt AS cnt
    ON cnt.c01 = cty.d03
),
top_staff_by_amount_month AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS payment_month,
    p.p03 AS top_staff_id,
    SUM(CAST(p.p05 AS REAL)) AS top_staff_amount
  FROM pay AS p
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06),
    p.p03
),
top_staff_month_ranked AS (
  SELECT
    ts.*,
    ROW_NUMBER() OVER (
      PARTITION BY ts.customer_id, ts.payment_month
      ORDER BY ts.top_staff_amount DESC, ts.top_staff_id
    ) AS rn
  FROM top_staff_by_amount_month ts
)
SELECT
  t10.customer_id,
  cg.customer_first_name,
  cg.customer_last_name,
  cg.country_name,
  cg.city_name,
  t10.payment_month,
  ROUND(t10.month_amount, 2) AS month_amount,
  t10.payment_count,
  ROUND(t10.personal_avg_prev_months, 2) AS personal_avg_prev_months,
  ROUND(t10.month_amount / NULLIF(t10.personal_avg_prev_months, 0), 2) AS deviation_ratio,
  t10.pr AS country_top10_percent_rank,
  tsr.top_staff_id AS top_staff_id,
  st.o02 AS top_staff_first_name,
  st.o03 AS top_staff_last_name
FROM top10_country_month AS t10
JOIN customer_geo AS cg
  ON cg.customer_id = t10.customer_id
JOIN top_staff_month_ranked AS tsr
  ON tsr.customer_id = t10.customer_id
 AND tsr.payment_month = t10.payment_month
 AND tsr.rn = 1
LEFT JOIN stf AS st
  ON st.o01 = tsr.top_staff_id
ORDER BY
  t10.payment_month,
  t10.month_amount DESC,
  t10.customer_id;