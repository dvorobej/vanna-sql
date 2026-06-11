WITH monthly_customer AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS customer_store_id,
    st.j02 AS customer_store_name,
    ct.d02 AS city,
    cn.c02 AS country,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS payment_sum,
    MAX(p.p03) AS any_staff_id
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN sto AS st
    ON st.j01 = c.h02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS cn
    ON cn.c01 = ct.d03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    c.h01, c.h02, st.j02, ct.d02, cn.c02,
    date(p.p06, 'start of month')
),
monthly_with_prev AS (
  SELECT
    mc.*,
    AVG(mc.payment_sum) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS prev_2m_avg_payment_sum,
    COUNT(*) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS prev_2m_months_available
  FROM monthly_customer AS mc
),
store_month_stats AS (
  SELECT
    customer_store_id,
    month_start,
    payment_sum,
    payment_count,
    prev_2m_avg_payment_sum,
    prev_2m_months_available,
    ntile10
  FROM (
    SELECT
      mwp.*,
      PERCENT_RANK() OVER (
        PARTITION BY mwp.customer_store_id, mwp.month_start
        ORDER BY mwp.payment_sum
      ) AS pr,
      ROW_NUMBER() OVER (
        PARTITION BY mwp.customer_store_id, mwp.month_start
        ORDER BY mwp.payment_sum DESC
      ) AS rn_desc,
      COUNT(*) OVER (
        PARTITION BY mwp.customer_store_id, mwp.month_start
      ) AS cnt_customers
    FROM monthly_with_prev AS mwp
  ) x
),
store_top10 AS (
  SELECT
    customer_store_id,
    month_start,
    customer_id,
    customer_store_name,
    city,
    country,
    payment_sum,
    payment_count,
    prev_2m_avg_payment_sum,
    prev_2m_months_available,
    rn_desc,
    cnt_customers
  FROM (
    SELECT
      mwp.*,
      ROW_NUMBER() OVER (
        PARTITION BY mwp.customer_store_id, mwp.month_start
        ORDER BY mwp.payment_sum DESC
      ) AS rn_desc,
      COUNT(*) OVER (
        PARTITION BY mwp.customer_store_id, mwp.month_start
      ) AS cnt_customers
    FROM monthly_with_prev AS mwp
  ) y
  WHERE prev_2m_months_available = 2
    AND payment_count >= 3
    AND payment_sum >= 2.0 * prev_2m_avg_payment_sum
    AND rn_desc <= CAST(0.10 * cnt_customers + 0.999999 AS INT)
),
staff_top_by_customer_month AS (
  SELECT
    c.h01 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id,
    SUM(p.p05) AS staff_payment_sum,
    COUNT(*) AS staff_payment_count,
    ROW_NUMBER() OVER (
      PARTITION BY c.h01, date(p.p06, 'start of month')
      ORDER BY SUM(p.p05) DESC, COUNT(*) DESC, p.p03
    ) AS rn_staff
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    c.h01,
    date(p.p06, 'start of month'),
    p.p03
),
suspect_customers_all_months AS (
  SELECT
    customer_id
  FROM store_top10
  GROUP BY customer_id
  HAVING COUNT(*) = 12
)
SELECT
  st10.customer_store_name AS store_name,
  st10.city,
  st10.country,
  strftime('%Y-%m', st10.month_start) AS payment_month,
  ROUND(st10.payment_sum, 2) AS payment_sum,
  st10.payment_count,
  ROUND(st10.payment_sum - st10.prev_2m_avg_payment_sum, 2) AS deviation_from_prev_2m_avg,
  RANK() OVER (
    PARTITION BY st10.customer_store_id, st10.month_start
    ORDER BY st10.payment_sum DESC
  ) AS store_month_payment_rank,
  s.o02 AS staff_first_name,
  s.o03 AS staff_last_name,
  s.o06 AS staff_email,
  ROUND(stmb.staff_payment_sum, 2) AS top_staff_payment_sum
FROM store_top10 AS st10
JOIN suspect_customers_all_months AS sc
  ON sc.customer_id = st10.customer_id
JOIN staff_top_by_customer_month AS stmb
  ON stmb.customer_id = st10.customer_id
 AND stmb.month_start = st10.month_start
 AND stmb.rn_staff = 1
JOIN stf AS s
  ON s.o01 = stmb.staff_id
ORDER BY
  st10.customer_store_name,
  st10.month_start,
  store_month_payment_rank,
  st10.customer_id;