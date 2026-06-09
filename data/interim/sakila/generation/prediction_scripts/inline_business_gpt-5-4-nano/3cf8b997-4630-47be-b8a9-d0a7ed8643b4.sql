WITH monthly AS (
  SELECT
    p.p02 AS customer_id,
    c.h02 AS customer_store_id,
    strftime('%Y-%m', p.p06) AS payment_month,
    CAST(SUM(p.p05) AS REAL) AS month_total_amount,
    COUNT(*) AS payment_count
  FROM pay p
  JOIN cus c
    ON c.h01 = p.p02
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    c.h02,
    strftime('%Y-%m', p.p06)
),
hist AS (
  SELECT
    m.*,
    AVG(m.month_total_amount) OVER (
      PARTITION BY m.customer_id
      ORDER BY m.payment_month
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS prev2_months_avg_amount
  FROM monthly m
),
suspicious_months AS (
  SELECT
    h.*,
    1.0 * h.month_total_amount / NULLIF(h.prev2_months_avg_amount, 0) AS deviation_from_prev2_avg
  FROM hist h
  WHERE h.prev2_months_avg_amount IS NOT NULL
    AND h.payment_count >= 3
    AND h.month_total_amount >= 2.0 * h.prev2_months_avg_amount
),
store_top_decile_threshold AS (
  SELECT
    customer_store_id,
    payment_month,
    -- верхние 10% среди клиентов того же магазина в данном месяце
    -- threshold по значению month_total_amount
    (
      SELECT
        m2.month_total_amount
      FROM monthly m2
      WHERE m2.customer_store_id = sm.customer_store_id
        AND m2.payment_month = sm.payment_month
      ORDER BY m2.month_total_amount DESC
      LIMIT 1 OFFSET (
        (SELECT COUNT(*) FROM monthly m3
         WHERE m3.customer_store_id = sm.customer_store_id
           AND m3.payment_month = sm.payment_month) * 0.10 - 1
      )
    ) AS top10pct_threshold
  FROM suspicious_months sm
  GROUP BY customer_store_id, payment_month
),
filtered_months AS (
  SELECT
    sm.*
  FROM suspicious_months sm
  JOIN store_top_decile_threshold t
    ON t.customer_store_id = sm.customer_store_id
   AND t.payment_month = sm.payment_month
  WHERE sm.month_total_amount >= t.top10pct_threshold
),
client_all_months AS (
  -- клиенты, у которых ВСЕ месяцы 2005 имеют подозрительное условие
  -- считаем количество подозрительных месяцев и сравниваем с количеством месяцев в 2005 (12)
  SELECT
    fm.customer_id,
    fm.customer_store_id,
    COUNT(*) AS suspicious_months_count
  FROM filtered_months fm
  GROUP BY fm.customer_id, fm.customer_store_id
  HAVING COUNT(*) = 12
),
pay_month_staff_max AS (
  SELECT
    p.p02 AS customer_id,
    c.h02 AS customer_store_id,
    strftime('%Y-%m', p.p06) AS payment_month,
    -- сотрудник с наибольшей суммой по этому клиенту в этот месяц
    FIRST_VALUE(p.p03) OVER (
      PARTITION BY p.p02, strftime('%Y-%m', p.p06)
      ORDER BY p.p05 DESC
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS top_staff_id,
    MAX(p.p05) AS max_single_payment_in_month
  FROM pay p
  JOIN cus c
    ON c.h01 = p.p02
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY p.p02, c.h02, strftime('%Y-%m', p.p06)
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS customer_store_id,
    ct.d02 AS customer_city,
    co.c02 AS customer_country
  FROM cus c
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ct ON ct.d01 = a.e05
  JOIN cnt co ON co.c01 = ct.d03
)
SELECT
  fm.customer_store_id AS store_id,
  sg.j02 AS store_manager_staff_id,
  cg.customer_country,
  cg.customer_city,
  fm.payment_month,
  fm.customer_id,
  c.h03 AS customer_first_name,
  c.h04 AS customer_last_name,
  ROUND(fm.month_total_amount, 2) AS month_total_amount,
  fm.payment_count,
  ROUND(fm.deviation_from_prev2_avg, 4) AS deviation_from_prev2_avg,
  DENSE_RANK() OVER (
    PARTITION BY fm.customer_store_id, fm.payment_month
    ORDER BY fm.month_total_amount DESC
  ) AS store_month_rank,
  ps.top_staff_id AS top_staff_id_in_month,
  st.o02 || ' ' || st.o03 AS top_staff_full_name
FROM filtered_months fm
JOIN client_all_months cam
  ON cam.customer_id = fm.customer_id
 AND cam.customer_store_id = fm.customer_store_id
JOIN cus c
  ON c.h01 = fm.customer_id
JOIN sto sg
  ON sg.j01 = fm.customer_store_id
JOIN customer_geo cg
  ON cg.customer_id = fm.customer_id
 AND cg.customer_store_id = fm.customer_store_id
JOIN pay_month_staff_max ps
  ON ps.customer_id = fm.customer_id
 AND ps.customer_store_id = fm.customer_store_id
 AND ps.payment_month = fm.payment_month
JOIN stf st
  ON st.o01 = ps.top_staff_id_in_month
ORDER BY
  fm.customer_store_id,
  fm.payment_month,
  fm.customer_id;