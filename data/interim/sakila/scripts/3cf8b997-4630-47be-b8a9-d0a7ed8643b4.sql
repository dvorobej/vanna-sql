WITH RECURSIVE months(month_start) AS (
  SELECT date('2004-11-01')
  UNION ALL
  SELECT date(month_start, '+1 month')
  FROM months
  WHERE month_start < date('2005-12-01')
),
customer_month_pay AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(p.p05) AS month_amount,
    COUNT(*) AS payment_count
  FROM pay AS p
  WHERE p.p04 IS NOT NULL
    AND p.p06 >= '2004-11-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
customer_months AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    m.month_start,
    COALESCE(cmp.month_amount, 0.0) AS month_amount,
    COALESCE(cmp.payment_count, 0) AS payment_count
  FROM cus AS c
  CROSS JOIN months AS m
  LEFT JOIN customer_month_pay AS cmp
    ON cmp.customer_id = c.h01
   AND cmp.month_start = m.month_start
),
monthly_with_avg AS (
  SELECT
    customer_id,
    store_id,
    month_start,
    month_amount,
    payment_count,
    (
      LAG(month_amount, 1) OVER (
        PARTITION BY customer_id
        ORDER BY month_start
      )
      +
      LAG(month_amount, 2) OVER (
        PARTITION BY customer_id
        ORDER BY month_start
      )
    ) / 2.0 AS prev2_avg_amount
  FROM customer_months
),
suspicious_months AS (
  SELECT
    customer_id,
    store_id,
    month_start,
    month_amount,
    payment_count,
    prev2_avg_amount,
    month_amount - prev2_avg_amount AS deviation_from_avg,
    month_amount / NULLIF(prev2_avg_amount, 0) AS ratio_to_avg
  FROM monthly_with_avg
  WHERE month_start >= date('2005-01-01')
    AND month_start < date('2006-01-01')
    AND payment_count >= 3
    AND prev2_avg_amount > 0
    AND month_amount >= prev2_avg_amount * 2.0
),
customer_suspicious_totals AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    COALESCE(SUM(sm.month_amount), 0.0) AS suspicious_total_amount
  FROM cus AS c
  LEFT JOIN suspicious_months AS sm
    ON sm.customer_id = c.h01
  GROUP BY
    c.h01,
    c.h02
),
ranked_customers AS (
  SELECT
    customer_id,
    store_id,
    suspicious_total_amount,
    RANK() OVER (
      PARTITION BY store_id
      ORDER BY suspicious_total_amount DESC
    ) AS store_rank,
    COUNT(*) OVER (
      PARTITION BY store_id
    ) AS store_customer_count
  FROM customer_suspicious_totals
),
top_customers AS (
  SELECT
    customer_id,
    store_id,
    suspicious_total_amount,
    store_rank,
    store_customer_count
  FROM ranked_customers
  WHERE suspicious_total_amount > 0
    AND store_rank <= (store_customer_count + 9) / 10
),
staff_month_pay AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id,
    SUM(p.p05) AS staff_month_amount,
    COUNT(*) AS staff_payment_count
  FROM pay AS p
  WHERE p.p04 IS NOT NULL
    AND p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06, 'start of month'),
    p.p03
),
top_staff AS (
  SELECT
    customer_id,
    month_start,
    staff_id,
    staff_month_amount,
    staff_payment_count
  FROM (
    SELECT
      smp.*,
      ROW_NUMBER() OVER (
        PARTITION BY customer_id, month_start
        ORDER BY staff_month_amount DESC, staff_payment_count DESC, staff_id
      ) AS rn
    FROM staff_month_pay AS smp
  )
  WHERE rn = 1
)
SELECT
  sm.store_id,
  sm.customer_id,
  c.h03 AS customer_first_name,
  c.h04 AS customer_last_name,
  city.d02 AS customer_city,
  country.c02 AS customer_country,
  strftime('%Y-%m', sm.month_start) AS payment_month,
  ROUND(sm.month_amount, 2) AS month_payment_amount,
  sm.payment_count,
  ROUND(sm.prev2_avg_amount, 2) AS previous_2_month_avg_amount,
  ROUND(sm.deviation_from_avg, 2) AS deviation_from_avg,
  ROUND(sm.ratio_to_avg, 2) AS ratio_to_avg,
  ROUND(tc.suspicious_total_amount, 2) AS customer_suspicious_total_amount,
  tc.store_rank,
  tc.store_customer_count,
  st.o01 AS top_staff_id,
  st.o02 AS top_staff_first_name,
  st.o03 AS top_staff_last_name,
  st.o06 AS top_staff_email,
  ROUND(ts.staff_month_amount, 2) AS top_staff_payment_amount,
  ts.staff_payment_count AS top_staff_payment_count
FROM suspicious_months AS sm
JOIN top_customers AS tc
  ON tc.customer_id = sm.customer_id
 AND tc.store_id = sm.store_id
JOIN cus AS c
  ON c.h01 = sm.customer_id
JOIN adr AS a
  ON a.e01 = c.h06
JOIN cty AS city
  ON city.d01 = a.e05
JOIN cnt AS country
  ON country.c01 = city.d03
LEFT JOIN top_staff AS ts
  ON ts.customer_id = sm.customer_id
 AND ts.month_start = sm.month_start
LEFT JOIN stf AS st
  ON st.o01 = ts.staff_id
ORDER BY
  sm.store_id,
  tc.store_rank,
  tc.suspicious_total_amount DESC,
  sm.customer_id,
  sm.month_start;