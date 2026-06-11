SELECT date('2005-01-01') AS month_start
  UNION ALL
  SELECT date(month_start, '+1 month')
  FROM months
  WHERE month_start < '2005-12-01'
),
customer_base AS (
  SELECT
    cu.h01 AS customer_id,
    cu.h02 AS home_store_id,
    sto.j01 AS home_store_code,
    cty.d02 AS city,
    cnt.c02 AS country,
    cnt.c01 AS country_id
  FROM cus cu
  JOIN adr a ON a.e01 = cu.h06
  JOIN cty cty ON cty.d01 = a.e05
  JOIN cnt ON cnt.c01 = cty.d03
  JOIN sto ON sto.j01 = cu.h02
),
payments_monthly AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS payment_sum
  FROM pay p
  WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
payments_with_prev AS (
  SELECT
    pm.*,
    AVG(pm.payment_sum) OVER (
      PARTITION BY pm.customer_id
      ORDER BY pm.month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS prev_2_months_avg_sum
  FROM payments_monthly pm
),
monthly_joined AS (
  SELECT
    cb.home_store_id,
    cb.city,
    cb.country,
    cb.customer_id,
    m.month_start,
    COALESCE(pwp.payment_count, 0) AS payment_count,
    COALESCE(pwp.payment_sum, 0) AS payment_sum,
    pwp.prev_2_months_avg_sum
  FROM customer_base cb
  CROSS JOIN months m
  LEFT JOIN payments_with_prev pwp
    ON pwp.customer_id = cb.customer_id
   AND pwp.month_start = m.month_start
),
top10_store_month AS (
  SELECT
    mj.*,
    PERCENT_RANK() OVER (
      PARTITION BY mj.home_store_id, mj.month_start
      ORDER BY mj.payment_sum
    ) AS pr_store_month
  FROM monthly_joined mj
),
suspicious_months AS (
  SELECT *
  FROM top10_store_month
  WHERE month_start >= '2005-03-01'
    AND payment_count >= 3
    AND prev_2_months_avg_sum IS NOT NULL
    AND prev_2_months_avg_sum > 0
    AND payment_sum >= 2.0 * prev_2_months_avg_sum
    AND pr_store_month >= 0.9
),
customer_all_months AS (
  SELECT
    home_store_id,
    customer_id
  FROM suspicious_months
  GROUP BY home_store_id, customer_id
  HAVING COUNT(*) = 10
),
staff_top_by_customer_month AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id,
    SUM(p.p05) AS staff_payment_sum,
    COUNT(*) AS staff_payment_count,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, date(p.p06, 'start of month')
      ORDER BY SUM(p.p05) DESC, COUNT(*) DESC, p.p03
    ) AS rn
  FROM pay p
  WHERE p.p06 >= '2005-03-01' AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06, 'start of month'),
    p.p03
),
final_monthly AS (
  SELECT
    sm.home_store_id AS store_id,
    sm.city,
    sm.country,
    sm.customer_id,
    sm.month_start,
    sm.payment_sum,
    sm.payment_count,
    (sm.payment_sum - sm.prev_2_months_avg_sum) AS deviation_from_scrolling_avg,
    RANK() OVER (
      PARTITION BY sm.home_store_id, sm.month_start
      ORDER BY sm.payment_sum DESC
    ) AS store_month_rank,
    stb.staff_id AS top_staff_id,
    stb.staff_payment_sum AS top_staff_payment_sum
  FROM suspicious_months sm
  JOIN customer_all_months cam
    ON cam.customer_id = sm.customer_id
   AND cam.home_store_id = sm.home_store_id
  LEFT JOIN staff_top_by_customer_month stb
    ON stb.customer_id = sm.customer_id
   AND stb.month_start = sm.month_start
   AND stb.rn = 1
)
SELECT
  fm.store_id,
  fm.city,
  fm.country,
  strftime('%Y-%m', fm.month_start) AS month,
  ROUND(fm.payment_sum, 2) AS payment_sum,
  fm.payment_count,
  ROUND(fm.deviation_from_scrolling_avg, 2) AS deviation_from_scrolling_avg,
  fm.store_month_rank AS store_rank_in_month,
  st.o02 AS staff_first_name,
  st.o03 AS staff_last_name,
  fm.top_staff_id AS staff_id,
  ROUND(fm.top_staff_payment_sum, 2) AS top_staff_payment_sum,
  cu.h03 AS customer_first_name,
  cu.h04 AS customer_last_name
FROM final_monthly fm
JOIN cus cu ON cu.h01 = fm.customer_id
LEFT JOIN stf st ON st.o01 = fm.top_staff_id
ORDER BY
  fm.store_id,
  fm.month_start,
  fm.store_month_rank,
  fm.customer_id;