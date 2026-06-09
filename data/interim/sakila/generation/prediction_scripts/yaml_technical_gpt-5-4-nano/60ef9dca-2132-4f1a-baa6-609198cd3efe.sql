WITH monthly_pay AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    strftime('%Y-%m', p.p06) AS payment_month,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS month_amount
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06, 'start of month'),
    strftime('%Y-%m', p.p06)
),
customer_year_avg AS (
  SELECT
    customer_id,
    AVG(month_amount) AS personal_monthly_avg
  FROM monthly_pay
  GROUP BY customer_id
),
monthly_scored AS (
  SELECT
    mp.customer_id,
    mp.payment_month,
    mp.month_start,
    mp.payment_count,
    mp.month_amount,
    cya.personal_monthly_avg,
    (mp.month_amount - cya.personal_monthly_avg) AS deviation_from_personal_avg,
    RANK() OVER (
      PARTITION BY cu.h02, mp.payment_month
      ORDER BY mp.month_amount DESC
    ) AS rank_in_store_month
  FROM monthly_pay mp
  JOIN cus cu
    ON cu.h01 = mp.customer_id
  JOIN customer_year_avg cya
    ON cya.customer_id = mp.customer_id
),
store_month_counts AS (
  SELECT
    cu.h02 AS store_id,
    ms.payment_month,
    COUNT(*) AS customers_in_store_month
  FROM monthly_scored ms
  JOIN cus cu
    ON cu.h01 = ms.customer_id
  GROUP BY cu.h02, ms.payment_month
),
monthly_top5 AS (
  SELECT
    ms.*,
    smc.customers_in_store_month,
    ROUND(0.05 * smc.customers_in_store_month, 0) AS top5_cutoff_by_count
  FROM monthly_scored ms
  JOIN store_month_counts smc
    ON smc.store_id = (
      SELECT h02 FROM cus WHERE h01 = ms.customer_id
    )
   AND smc.payment_month = ms.payment_month
),
qualified_months AS (
  SELECT
    m.*,
    (
      m.rank_in_store_month <= (m.top5_cutoff_by_count + 0.0001)
    ) AS is_top5
  FROM monthly_top5 m
  WHERE m.personal_monthly_avg > 0
    AND m.month_amount > m.personal_monthly_avg * 2
    AND m.rank_in_store_month <= (m.top5_cutoff_by_count + 0.0001)
),
cust_all_months AS (
  SELECT
    customer_id
  FROM qualified_months
  GROUP BY customer_id
  HAVING COUNT(*) = 12
),
last_staff_per_month AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    MAX(p.p06) AS last_payment_date
  FROM pay p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
last_staff_id AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS last_staff_id
  FROM pay p
  JOIN last_staff_per_month l
    ON l.customer_id = p.p02
   AND l.month_start = date(p.p06, 'start of month')
   AND l.last_payment_date = p.p06
)
SELECT
  cm.customer_id AS h01,
  (c.h03 || ' ' || c.h04) AS customer_name,
  c.h02 AS store_id,
  ct.c02 AS country,
  cty.d02 AS city,
  q.payment_month,
  q.payment_count,
  ROUND(q.month_amount, 2) AS month_amount,
  ROUND(q.personal_monthly_avg, 2) AS personal_monthly_avg,
  ROUND(q.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
  q.rank_in_store_month AS rank_in_store_month,
  ls.last_staff_id AS last_staff_o01,
  st.o02 || ' ' || st.o03 AS last_staff_name
FROM cust_all_months cam
JOIN cus c
  ON c.h01 = cam.customer_id
JOIN adr a
  ON a.e01 = c.h06
JOIN cty
  ON cty.d01 = a.e05
JOIN cnt ct
  ON ct.c01 = cty.d03
JOIN qualified_months q
  ON q.customer_id = cam.customer_id
JOIN last_staff_id ls
  ON ls.customer_id = q.customer_id
 AND ls.month_start = q.month_start
JOIN stf st
  ON st.o01 = ls.last_staff_id
ORDER BY
  country,
  cty.d02,
  store_id,
  q.payment_month;