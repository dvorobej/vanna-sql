WITH payments_2005 AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    CAST(p.p05 AS REAL) AS payment_amount,
    date(p.p06, 'start of month') AS month_start
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    a.e05 AS city_id,
    ct.d02 AS city_name,
    ct.d03 AS country_id,
    cn.c02 AS country_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ct ON ct.d01 = a.e05
  JOIN cnt AS cn ON cn.c01 = ct.d03
),
monthly_customer AS (
  SELECT
    p.customer_id,
    p.month_start,
    SUM(p.payment_amount) AS monthly_sum,
    COUNT(*) AS monthly_payment_count
  FROM payments_2005 AS p
  GROUP BY p.customer_id, p.month_start
),
customer_personal_avg AS (
  SELECT
    customer_id,
    AVG(monthly_sum) AS personal_avg_monthly_sum
  FROM monthly_customer
  GROUP BY customer_id
),
monthly_store_ranks AS (
  SELECT
    mc.customer_id,
    mc.month_start,
    mc.monthly_sum,
    mc.monthly_payment_count,
    cpa.personal_avg_monthly_sum,
    PERCENT_RANK() OVER (
      PARTITION BY c.customer_id /* placeholder, will be overwritten below */
      ORDER BY mc.monthly_sum DESC
    ) AS dummy
  FROM monthly_customer mc
  JOIN customer_geo c ON c.customer_id = mc.customer_id
  JOIN customer_personal_avg cpa ON cpa.customer_id = mc.customer_id
),
monthly_store_ranked AS (
  SELECT
    mc.customer_id,
    cg.store_id,
    cg.city_name,
    cg.country_name,
    mc.month_start,
    mc.monthly_sum,
    mc.monthly_payment_count,
    cpa.personal_avg_monthly_sum,
    RANK() OVER (
      PARTITION BY cg.store_id, mc.month_start
      ORDER BY mc.monthly_sum DESC
    ) AS store_month_rank,
    COUNT(*) OVER (
      PARTITION BY cg.store_id, mc.month_start
    ) AS store_month_customer_count
  FROM monthly_customer mc
  JOIN customer_geo cg ON cg.customer_id = mc.customer_id
  JOIN customer_personal_avg cpa ON cpa.customer_id = mc.customer_id
),
monthly_last_staff AS (
  SELECT
    p.customer_id,
    p.month_start,
    p.staff_id,
    ROW_NUMBER() OVER (
      PARTITION BY p.customer_id, p.month_start
      ORDER BY p.payment_id DESC
    ) AS rn
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
),
last_staff_pick AS (
  SELECT
    customer_id,
    month_start,
    staff_id
  FROM monthly_last_staff
  WHERE rn = 1
),
filtered_monthly AS (
  SELECT
    msr.customer_id,
    msr.store_id,
    msr.city_name,
    msr.country_name,
    msr.month_start,
    msr.monthly_sum,
    msr.monthly_payment_count,
    (msr.monthly_sum - msr.personal_avg_monthly_sum) AS deviation_from_personal_avg,
    msr.store_month_rank,
    msr.personal_avg_monthly_sum,
    (1.0 * msr.store_month_rank / msr.store_month_customer_count) AS rank_fraction
  FROM monthly_store_ranked msr
  WHERE
    msr.monthly_sum > msr.personal_avg_monthly_sum * 2
    AND (1.0 * msr.store_month_rank) <= (0.05 * msr.store_month_customer_count)
),
qualified_customers AS (
  SELECT
    customer_id
  FROM filtered_monthly
  GROUP BY customer_id
  HAVING COUNT(DISTINCT month_start) = 12
)
SELECT
  fm.customer_id,
  fm.store_id,
  fm.city_name,
  fm.country_name,
  strftime('%Y-%m', fm.month_start) AS month,
  ROUND(fm.monthly_sum, 2) AS month_payment_sum,
  fm.monthly_payment_count,
  ROUND(fm.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
  fm.store_month_rank AS store_month_rank,
  st.o01 AS last_staff_id,
  st.o02 || ' ' || st.o03 AS last_staff_full_name
FROM filtered_monthly fm
JOIN qualified_customers qc
  ON qc.customer_id = fm.customer_id
LEFT JOIN last_staff_pick lsp
  ON lsp.customer_id = fm.customer_id
 AND lsp.month_start = fm.month_start
LEFT JOIN stf st
  ON st.o01 = lsp.staff_id
ORDER BY
  fm.customer_id,
  fm.month_start;