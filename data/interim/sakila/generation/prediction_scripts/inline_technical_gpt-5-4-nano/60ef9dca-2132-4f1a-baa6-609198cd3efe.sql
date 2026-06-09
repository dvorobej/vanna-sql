WITH monthly_pay AS (
  SELECT
    p.p02 AS customer_id,
    p.p06 AS payment_month_start,
    strftime('%Y-%m', p.p06) AS payment_month,
    SUM(p.p05) AS month_amount,
    COUNT(p.p01) AS payment_count
  FROM pay AS p
  GROUP BY
    p.p02,
    p.p06,
    strftime('%Y-%m', p.p06)
),
customer_year_avg AS (
  SELECT
    customer_id,
    AVG(month_amount) AS personal_avg_month_amount
  FROM monthly_pay
  GROUP BY customer_id
),
store_month_rank AS (
  SELECT
    mp.*,
    RANK() OVER (
      PARTITION BY c.h02, mp.payment_month
      ORDER BY mp.month_amount DESC
    ) AS store_month_rank,
    COUNT(*) OVER (
      PARTITION BY c.h02, mp.payment_month
    ) AS store_month_customer_count
  FROM monthly_pay mp
  JOIN cus c
    ON c.h01 = mp.customer_id
),
qualified_months AS (
  SELECT
    smr.*,
    cya.personal_avg_month_amount,
    st_top_cnt AS top_5_percent_threshold
  FROM store_month_rank smr
  JOIN customer_year_avg cya
    ON cya.customer_id = smr.customer_id
  CROSS JOIN (
    SELECT 1 AS st_top_cnt
  )
  -- threshold by row_number position: keep where rank <= ceil(N*0.05)
),
qualified_months_final AS (
  SELECT
    q.*,
    CAST(CEIL(q.store_month_customer_count * 0.05) AS INTEGER) AS top_5_percent_cnt
  FROM qualified_months q
),
all_months_2005_qualified AS (
  SELECT
    qmf.customer_id
  FROM qualified_months_final qmf
  WHERE qmf.personal_avg_month_amount IS NOT NULL
    AND qmf.month_amount > 2.0 * qmf.personal_avg_month_amount
    AND qmf.store_month_rank <= CAST(CEIL(qmf.store_month_customer_count * 0.05) AS INTEGER)
  GROUP BY qmf.customer_id
  HAVING
    COUNT(*) = (
      SELECT COUNT(*)
      FROM (
        SELECT DISTINCT strftime('%Y-%m', p06) AS m
        FROM pay
        WHERE p06 >= '2005-01-01' AND p06 < '2006-01-01'
      ) x
    )
),
last_staff_per_month AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS payment_month,
    p.p03 AS last_staff_id
  FROM pay p
  JOIN (
    SELECT
      p2.p02 AS customer_id,
      strftime('%Y-%m', p2.p06) AS payment_month,
      MAX(p2.p06) AS max_payment_dt
    FROM pay p2
    WHERE p2.p06 >= '2005-01-01' AND p2.p06 < '2006-01-01'
    GROUP BY p2.p02, strftime('%Y-%m', p2.p06)
  ) mx
    ON mx.customer_id = p.p02
   AND mx.payment_month = strftime('%Y-%m', p.p06)
   AND mx.max_payment_dt = p.p06
  WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    ct.d02 AS city,
    cn.c02 AS country
  FROM cus c
  JOIN adr a
    ON a.e01 = c.h06
  JOIN cty ct
    ON ct.d01 = a.e05
  JOIN cnt cn
    ON cn.c01 = ct.d03
)
SELECT
  qmf.customer_id,
  cg.customer_name,
  cg.country,
  cg.city,
  qmf.payment_month,
  ROUND(qmf.month_amount, 2) AS month_amount,
  qmf.payment_count,
  ROUND(qmf.personal_avg_month_amount, 2) AS personal_avg_month_amount,
  ROUND(qmf.month_amount - qmf.personal_avg_month_amount, 2) AS deviation_from_personal_avg,
  qmf.store_month_rank AS store_month_amount_rank,
  lsm.last_staff_id,
  st.o02 || ' ' || st.o03 AS last_staff_name
FROM qualified_months_final qmf
JOIN all_months_2005_qualified am
  ON am.customer_id = qmf.customer_id
JOIN customer_geo cg
  ON cg.customer_id = qmf.customer_id
LEFT JOIN last_staff_per_month lsm
  ON lsm.customer_id = qmf.customer_id
 AND lsm.payment_month = qmf.payment_month
LEFT JOIN stf st
  ON st.o01 = lsm.last_staff_id
WHERE qmf.payment_month >= '2005-01'
  AND qmf.payment_month <= '2005-12'
  AND qmf.month_amount > 2.0 * qmf.personal_avg_month_amount
  AND qmf.store_month_rank <= CAST(CEIL(qmf.store_month_customer_count * 0.05) AS INTEGER)
ORDER BY
  cg.country,
  cg.city,
  qmf.customer_id,
  qmf.payment_month;