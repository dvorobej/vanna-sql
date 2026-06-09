WITH month_list AS (
  SELECT date('2005-01-01', printf('+%d months', n)) AS month_start
  FROM (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
        UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10 UNION ALL SELECT 11)
),
customer_months AS (
  SELECT
    c.h01 AS customer_id,
    s.j01 AS customer_store_id,
    ci.d02 AS customer_city,
    cn.c02 AS customer_country,
    ml.month_start
  FROM cus c
  JOIN sto s ON s.j01 = c.h02
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ci ON ci.d01 = a.e05
  JOIN cnt cn ON cn.c01 = ci.d03
  CROSS JOIN month_list ml
),
payments_2005 AS (
  SELECT
    p.p02 AS customer_id,
    c.h02 AS customer_store_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS month_sum
  FROM pay p
  JOIN cus c ON c.h01 = p.p02
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02, c.h02, date(p.p06, 'start of month')
),
monthly_full AS (
  SELECT
    cm.customer_id,
    cm.customer_store_id,
    cm.customer_city,
    cm.customer_country,
    cm.month_start,
    COALESCE(p.payment_count, 0) AS payment_count,
    COALESCE(p.month_sum, 0.0) AS month_sum
  FROM customer_months cm
  LEFT JOIN payments_2005 p
    ON p.customer_id = cm.customer_id
   AND p.customer_store_id = cm.customer_store_id
   AND p.month_start = cm.month_start
),
monthly_scored AS (
  SELECT
    mf.*,
    AVG(month_sum) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS rolling_prev_2_avg_month_sum
  FROM monthly_full mf
),
suspicious_months AS (
  SELECT
    ms.*
  FROM monthly_scored ms
  WHERE ms.payment_count >= 3
    AND ms.rolling_prev_2_avg_month_sum IS NOT NULL
    AND ms.rolling_prev_2_avg_month_sum > 0
    AND ms.month_sum >= 2.0 * ms.rolling_prev_2_avg_month_sum
),
store_month_ranked AS (
  SELECT
    sm.*,
    PERCENT_RANK() OVER (
      PARTITION BY customer_store_id, month_start
      ORDER BY month_sum
    ) AS pr,
    RANK() OVER (
      PARTITION BY customer_store_id, month_start
      ORDER BY month_sum DESC
    ) AS store_rank_desc
  FROM suspicious_months sm
),
top_10pct_months AS (
  SELECT
    *
  FROM store_month_ranked
  WHERE pr >= 0.90
),
client_qualifying AS (
  -- требование "в каждом месяце 2005 года": фактически сработает только для месяцев начиная с марта (т.к. есть предыдущие 2 месяца)
  SELECT
    customer_id
  FROM top_10pct_months
  GROUP BY customer_id
  HAVING COUNT(*) = 10
)
SELECT
  c.customer_store_id AS store_id,
  c.customer_city AS city,
  c.customer_country AS country,
  strftime('%Y-%m', tm.month_start) AS payment_month,
  ROUND(tm.month_sum, 2) AS month_sum,
  tm.payment_count,
  ROUND(tm.month_sum - tm.rolling_prev_2_avg_month_sum, 2) AS deviation_from_rolling_avg,
  RANK() OVER (
    PARTITION BY tm.customer_store_id, tm.month_start
    ORDER BY tm.month_sum DESC
  ) AS store_month_rank,
  st.o01 AS staff_id,
  st.o02 AS staff_first_name,
  st.o03 AS staff_last_name,
  ROUND(tmx.max_staff_payment_sum, 2) AS staff_max_month_payment_sum
FROM top_10pct_months tm
JOIN client_qualifying q
  ON q.customer_id = tm.customer_id
JOIN (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    MAX(p.p05) AS any_max_payment
  FROM pay p
  WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
  GROUP BY p.p02, date(p.p06, 'start of month')
) dummy ON dummy.customer_id = tm.customer_id AND dummy.month_start = tm.month_start
JOIN cus c
  ON c.h01 = tm.customer_id
JOIN (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id,
    SUM(p.p05) AS max_staff_payment_sum,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, date(p.p06, 'start of month')
      ORDER BY SUM(p.p05) DESC, p.p03
    ) AS rn
  FROM pay p
  WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
  GROUP BY p.p02, date(p.p06, 'start of month'), p.p03
) tmx
  ON tmx.customer_id = tm.customer_id
 AND tmx.month_start = tm.month_start
 AND tmx.rn = 1
JOIN stf st
  ON st.o01 = tmx.staff_id
ORDER BY
  tm.customer_store_id,
  tm.month_start,
  tm.month_sum DESC;