WITH payments_2005 AS (
  SELECT
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p05 AS payment_amount,
    date(p.p06,'start of month') AS month_start,
    strftime('%Y-%m', p.p06) AS month_str,
    p.p04 AS rental_id
  FROM pay p
  WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
),
customer_store AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id
  FROM cus c
),
customer_address_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    ci.d02 AS city_name,
    co.c02 AS country_name
  FROM cus c
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ci ON ci.d01 = a.e05
  JOIN cnt co ON co.c01 = ci.d03
),
monthly_customer AS (
  SELECT
    p.customer_id,
    cs.store_id,
    p.month_start,
    COUNT(*) AS payment_count,
    SUM(p.payment_amount) AS monthly_sum
  FROM payments_2005 p
  JOIN customer_store cs ON cs.customer_id = p.customer_id
  GROUP BY
    p.customer_id,
    cs.store_id,
    p.month_start
),
monthly_personal AS (
  SELECT
    mc.*,
    AVG(mc.monthly_sum) OVER (PARTITION BY mc.customer_id) AS personal_avg_monthly_sum
  FROM monthly_customer mc
),
months_in_2005 AS (
  SELECT 0 AS k UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL
  SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL
  SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL
  SELECT 10 UNION ALL SELECT 11
),
customer_months_full AS (
  SELECT
    mc.customer_id,
    mc.store_id,
    date('2005-01-01', '+' || m.k || ' months') AS month_start
  FROM (SELECT DISTINCT customer_id, store_id FROM monthly_customer) mc
  CROSS JOIN months_in_2005 m
),
monthly_with_defaults AS (
  SELECT
    cmf.customer_id,
    cmf.store_id,
    cmf.month_start,
    COALESCE(mp.payment_count,0) AS payment_count,
    COALESCE(mp.monthly_sum,0) AS monthly_sum
  FROM customer_months_full cmf
  LEFT JOIN monthly_personal mp
    ON mp.customer_id = cmf.customer_id
   AND mp.store_id = cmf.store_id
   AND mp.month_start = cmf.month_start
),
personal_avg AS (
  SELECT
    customer_id,
    AVG(monthly_sum) AS personal_avg_monthly_sum
  FROM monthly_with_defaults
  GROUP BY customer_id
),
monthly_rank_store AS (
  SELECT
    mw.*,
    pa.personal_avg_monthly_sum,
    RANK() OVER (
      PARTITION BY mw.store_id, mw.month_start
      ORDER BY mw.monthly_sum DESC
    ) AS store_month_rank,
    COUNT(*) OVER (
      PARTITION BY mw.store_id, mw.month_start
    ) AS store_month_customer_count
  FROM monthly_with_defaults mw
  JOIN personal_avg pa ON pa.customer_id = mw.customer_id
),
top5pct_store_month AS (
  SELECT
    mr.*,
    CAST((mr.store_month_customer_count * 0.05) AS INT) AS top5pct_threshold
  FROM monthly_rank_store mr
),
qualified_customers AS (
  SELECT
    customer_id,
    store_id
  FROM top5pct_store_month
  WHERE
    monthly_sum > personal_avg_monthly_sum * 2
    AND store_month_rank <= (store_month_customer_count * 0.05)
  GROUP BY customer_id, store_id
  HAVING COUNT(*) = 12
),
top_staff_per_month AS (
  SELECT
    p.customer_id,
    cs.store_id,
    date(p.p06,'start of month') AS month_start,
    p.staff_id,
    SUM(p.p05) AS staff_month_sum,
    ROW_NUMBER() OVER (
      PARTITION BY p.customer_id, cs.store_id, date(p.p06,'start of month')
      ORDER BY SUM(p.p05) DESC, p.staff_id
    ) AS rn
  FROM payments_2005 p
  JOIN customer_store cs ON cs.customer_id = p.customer_id
  GROUP BY
    p.customer_id,
    cs.store_id,
    date(p.p06,'start of month'),
    p.staff_id
)
SELECT
  t.customer_id,
  t.store_id AS store_id,
  g.city_name,
  g.country_name,
  strftime('%Y-%m', mm.month_start) AS month,
  ROUND(mm.monthly_sum,2) AS month_sum,
  mm.payment_count,
  ROUND(mm.monthly_sum - mm.personal_avg_monthly_sum,2) AS deviation_from_personal_avg,
  mm.store_month_rank AS store_month_rank,
  ts.staff_id AS last_staff_id,
  st.o02 || ' ' || st.o03 AS last_staff_name
FROM qualified_customers qc
JOIN monthly_rank_store mm
  ON mm.customer_id = qc.customer_id
 AND mm.store_id = qc.store_id
JOIN customer_address_geo g
  ON g.customer_id = qc.customer_id
 AND g.store_id = qc.store_id
JOIN top_staff_per_month ts
  ON ts.customer_id = qc.customer_id
 AND ts.store_id = qc.store_id
 AND ts.month_start = mm.month_start
 AND ts.rn = 1
JOIN stf st
  ON st.o01 = ts.staff_id
WHERE
  mm.monthly_sum > mm.personal_avg_monthly_sum * 2
  AND mm.store_month_rank <= (mm.store_month_customer_count * 0.05)
ORDER BY
  mm.month_start,
  qc.store_id,
  t.customer_id;