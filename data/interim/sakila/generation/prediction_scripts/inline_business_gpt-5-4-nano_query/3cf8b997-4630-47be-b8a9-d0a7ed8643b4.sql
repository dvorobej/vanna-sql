WITH monthly_customer AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS customer_store_id,
    c.h07 AS customer_active,
    c.h03 AS customer_first_name,
    c.h04 AS customer_last_name,
    ci.d02 AS customer_city,
    co.c02 AS customer_country,
    date(p.p06, 'start of month') AS month_start,
    COUNT(p.p01) AS payment_count,
    SUM(p.p05) AS month_total_amount
  FROM pay p
  JOIN cus c
    ON c.h01 = p.p02
  JOIN adr a
    ON a.e01 = c.h06
  JOIN cty ci
    ON ci.d01 = a.e05
  JOIN cnt co
    ON co.c01 = ci.d03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    c.h01, c.h02, c.h03, c.h04, ci.d02, co.c02, date(p.p06, 'start of month')
),
monthly_with_history AS (
  SELECT
    mc.*,
    AVG(mc.month_total_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS prev2_month_avg_amount
  FROM monthly_customer mc
),
monthly_with_top10_flag AS (
  SELECT
    mwh.*,
    (
      RANK() OVER (
        PARTITION BY mwh.customer_store_id, mwh.month_start
        ORDER BY mwh.month_total_amount DESC
      ) * 1.0
      / NULLIF(
          COUNT(*) OVER (PARTITION BY mwh.customer_store_id, mwh.month_start),
          0
        )
    ) AS store_month_share_rank
  FROM monthly_with_history mwh
),
suspicious_months AS (
  SELECT
    m.*,
    (m.month_total_amount - m.prev2_month_avg_amount) AS deviation_from_prev2_avg,
    RANK() OVER (
      PARTITION BY m.customer_store_id, m.month_start
      ORDER BY m.month_total_amount DESC
    ) AS store_month_rank
  FROM monthly_with_top10_flag m
  WHERE m.prev2_month_avg_amount IS NOT NULL
    AND m.payment_count >= 3
    AND m.month_total_amount >= 2.0 * m.prev2_month_avg_amount
    AND m.store_month_share_rank <= 0.10
),
top_staff_by_customer_month AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id,
    SUM(p.p05) AS staff_total_amount,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, date(p.p06, 'start of month')
      ORDER BY SUM(p.p05) DESC, COUNT(*) DESC, p.p03
    ) AS rn
  FROM pay p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    p.p02, date(p.p06, 'start of month'), p.p03
),
final_staff AS (
  SELECT
    ts.customer_id,
    ts.month_start,
    st.o02 AS staff_first_name,
    st.o03 AS staff_last_name,
    ts.staff_id,
    ts.staff_total_amount
  FROM top_staff_by_customer_month ts
  JOIN stf st
    ON st.o01 = ts.staff_id
  WHERE ts.rn = 1
),
clients_with_all_months AS (
  SELECT
    sm.customer_id
  FROM suspicious_months sm
  GROUP BY sm.customer_id
  HAVING COUNT(DISTINCT sm.month_start) = 12
)
SELECT
  sm.customer_store_id AS store_id,
  sm.customer_city AS city,
  sm.customer_country AS country,
  strftime('%Y-%m', sm.month_start) AS month,
  sm.month_total_amount AS month_amount,
  sm.payment_count AS payment_count,
  sm.deviation_from_prev2_avg AS deviation_from_scrolling_avg,
  sm.store_month_rank AS store_month_rank,
  sm.customer_id,
  fs.staff_first_name,
  fs.staff_last_name,
  fs.staff_id,
  fs.staff_total_amount AS top_staff_month_amount
FROM suspicious_months sm
JOIN clients_with_all_months c
  ON c.customer_id = sm.customer_id
JOIN final_staff fs
  ON fs.customer_id = sm.customer_id
 AND fs.month_start = sm.month_start
ORDER BY
  sm.customer_store_id,
  sm.month_start,
  sm.store_month_rank,
  sm.customer_id;