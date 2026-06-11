WITH monthly AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    date(p.p06, 'start of month') AS month_start,
    strftime('%Y-%m', p.p06) AS month_ym,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS month_amount
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    c.h01, c.h02, c.h03, c.h04, date(p.p06, 'start of month')
),
personal_avg AS (
  SELECT
    m.customer_id,
    m.store_id,
    AVG(m.month_amount) AS personal_avg_month_amount
  FROM monthly AS m
  GROUP BY m.customer_id, m.store_id
),
store_month_ranked AS (
  SELECT
    m.*,
    RANK() OVER (
      PARTITION BY m.store_id, m.month_start
      ORDER BY m.month_amount DESC
    ) AS store_month_amount_rank,
    COUNT(*) OVER (
      PARTITION BY m.store_id, m.month_start
    ) AS store_month_customers_cnt
  FROM monthly AS m
),
store_month_top5pct AS (
  SELECT
    smr.*,
    (smr.store_month_customers_cnt * 0.05) AS top5pct_threshold
  FROM store_month_ranked AS smr
),
monthly_staff_last AS (
  SELECT
    p.p02 AS customer_id,
    c.h02 AS store_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, date(p.p06, 'start of month')
      ORDER BY p.p06 DESC, p.p01 DESC
    ) AS rn
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
),
monthly_staff_last_one AS (
  SELECT
    ms.customer_id,
    ms.store_id,
    ms.month_start,
    ms.staff_id
  FROM monthly_staff_last AS ms
  WHERE ms.rn = 1
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    a.e05 AS city_id,
    ct.d02 AS city_name,
    cn.c02 AS country_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS cn
    ON cn.c01 = ct.d03
),
qualified_months AS (
  SELECT
    smt.customer_id,
    smt.store_id,
    smt.first_name,
    smt.last_name,
    smt.month_start,
    smt.month_ym,
    smt.payment_count,
    smt.month_amount,
    pa.personal_avg_month_amount,
    (smt.month_amount - pa.personal_avg_month_amount) AS deviation_from_personal_avg,
    smt.store_month_amount_rank,
    smt.store_month_customers_cnt,
    geo.city_name,
    geo.country_name,
    ms.staff_id
  FROM store_month_top5pct AS smt
  JOIN personal_avg AS pa
    ON pa.customer_id = smt.customer_id
   AND pa.store_id = smt.store_id
  JOIN customer_geo AS geo
    ON geo.customer_id = smt.customer_id
  JOIN monthly_staff_last_one AS ms
    ON ms.customer_id = smt.customer_id
   AND ms.store_id = smt.store_id
   AND ms.month_start = smt.month_start
  WHERE
    smt.month_amount > pa.personal_avg_month_amount * 2
    AND smt.store_month_amount_rank <= CAST( (smt.store_month_customers_cnt * 0.05) + 0.9999 AS INT)
),
clients_all_2005_months AS (
  SELECT
    qm.customer_id,
    qm.store_id,
    COUNT(*) AS matched_months_cnt
  FROM qualified_months AS qm
  GROUP BY qm.customer_id, qm.store_id
  HAVING COUNT(*) = 12
)
SELECT
  qm.customer_id AS h01,
  qm.first_name,
  qm.last_name,
  qm.store_id AS h02,
  qm.country_name,
  qm.city_name,
  qm.month_ym AS month,
  qm.payment_count,
  ROUND(qm.month_amount, 2) AS month_sum,
  ROUND(qm.personal_avg_month_amount, 2) AS personal_avg_month_sum,
  ROUND(qm.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
  qm.store_month_amount_rank AS store_month_rank,
  qm.staff_id AS last_staff_id,
  (st.o02 || ' ' || st.o03) AS last_staff_name
FROM qualified_months AS qm
JOIN clients_all_2005_months AS cam
  ON cam.customer_id = qm.customer_id
 AND cam.store_id = qm.store_id
JOIN stf AS st
  ON st.o01 = qm.staff_id
ORDER BY
  qm.store_id,
  qm.month_start,
  qm.month_sum DESC,
  qm.customer_id;