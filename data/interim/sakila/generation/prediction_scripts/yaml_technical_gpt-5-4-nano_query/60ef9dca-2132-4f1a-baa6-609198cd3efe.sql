WITH monthly_customer AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS payment_month,
    date(p.p06, 'start of month') AS month_start,
    c.h02 AS store_id,
    c.h03 || ' ' || c.h04 AS customer_full_name,
    ct.d02 AS city_name,
    co.c02 AS country_name,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS month_total_amount
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ct.d03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06),
    date(p.p06, 'start of month'),
    c.h02,
    c.h03, c.h04,
    ct.d02,
    co.c02
),
customer_year_avg AS (
  SELECT
    customer_id,
    AVG(month_total_amount) AS personal_avg_monthly_amount
  FROM monthly_customer
  GROUP BY customer_id
),
ranked_in_store AS (
  SELECT
    mc.*,
    cya.personal_avg_monthly_amount,
    RANK() OVER (
      PARTITION BY mc.store_id, mc.month_start
      ORDER BY mc.month_total_amount DESC
    ) AS store_month_rank,
    COUNT(*) OVER (
      PARTITION BY mc.store_id, mc.month_start
    ) AS store_month_customer_count
  FROM monthly_customer AS mc
  JOIN customer_year_avg AS cya
    ON cya.customer_id = mc.customer_id
),
qualified_months AS (
  SELECT
    *
  FROM ranked_in_store
  WHERE
    month_total_amount > personal_avg_monthly_amount * 2
    AND store_month_rank <= (store_month_customer_count * 0.05)
),
months_2005_count AS (
  SELECT COUNT(*) AS months_cnt
  FROM monthly_customer
  WHERE month_start >= '2005-01-01' AND month_start < '2006-01-01'
),
customer_all_months AS (
  SELECT
    qm.customer_id
  FROM qualified_months AS qm
  CROSS JOIN months_2005_count AS mcnt
  GROUP BY qm.customer_id
  HAVING COUNT(DISTINCT qm.month_start) = mcnt.months_cnt
),
top_staff_per_month AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, date(p.p06, 'start of month')
      ORDER BY SUM(p.p05) DESC, COUNT(*) DESC, p.p03
    ) AS rn
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06, 'start of month'),
    p.p03
)
SELECT
  qm.customer_id,
  qm.store_id,
  qm.city_name,
  qm.country_name,
  qm.payment_month,
  ROUND(qm.month_total_amount, 2) AS month_total_amount,
  qm.payment_count,
  ROUND(qm.month_total_amount - qm.personal_avg_monthly_amount, 2) AS deviation_from_personal_avg,
  qm.store_month_rank AS store_month_rank,
  ts.staff_id AS last_staff_id,
  st.o02 || ' ' || st.o03 AS last_staff_name
FROM qualified_months AS qm
JOIN customer_all_months AS cam
  ON cam.customer_id = qm.customer_id
JOIN top_staff_per_month AS ts
  ON ts.customer_id = qm.customer_id
 AND ts.month_start = qm.month_start
 AND ts.rn = 1
JOIN stf AS st
  ON st.o01 = ts.staff_id
ORDER BY
  qm.customer_id,
  qm.month_start;