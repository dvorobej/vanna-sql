WITH payments_2005 AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p06 AS payment_date,
    strftime('%Y-%m', p.p06) AS payment_month
  FROM pay p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
),
customer_base AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    c.h02 AS home_store_id,
    co.c01 AS country_id,
    co.c02 AS country_name,
    ct.d01 AS city_id,
    ct.d02 AS city_name
  FROM cus c
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ct ON ct.d01 = a.e05
  JOIN cnt co ON co.c01 = ct.d03
),
monthly_customer AS (
  SELECT
    p.customer_id,
    p.payment_month,
    COUNT(p.payment_id) AS payment_count,
    SUM(p.payment_amount) AS month_total_amount
  FROM payments_2005 p
  GROUP BY p.customer_id, p.payment_month
),
customer_avg AS (
  SELECT
    customer_id,
    AVG(month_total_amount) AS avg_monthly_amount_2005
  FROM monthly_customer
  GROUP BY customer_id
),
country_month_ranked AS (
  SELECT
    mc.*,
    RANK() OVER (
      PARTITION BY cb.country_id, mc.payment_month
      ORDER BY mc.month_total_amount DESC
    ) AS country_month_payment_rank,
    COUNT(*) OVER (
      PARTITION BY cb.country_id, mc.payment_month
    ) AS country_month_customer_count
  FROM monthly_customer mc
  JOIN customer_base cb
    ON cb.customer_id = mc.customer_id
),
top10pct_country_month AS (
  SELECT
    cmr.*,
    (cmr.country_month_customer_count * 0.10) AS top10_threshold_float,
    CAST(cmr.country_month_customer_count * 0.10 AS INTEGER) AS top10_threshold_int
  FROM country_month_ranked cmr
),
last_top_staff AS (
  SELECT
    p.customer_id,
    strftime('%Y-%m', p.payment_date) AS payment_month,
    p.staff_id,
    ROW_NUMBER() OVER (
      PARTITION BY p.customer_id, strftime('%Y-%m', p.payment_date)
      ORDER BY p.payment_amount DESC, p.payment_id DESC
    ) AS rn
  FROM payments_2005 p
),
top_staff_in_month AS (
  SELECT
    lts.customer_id,
    lts.payment_month,
    lts.staff_id
  FROM last_top_staff lts
  WHERE lts.rn = 1
)
SELECT
  cb.customer_id,
  cb.country_name AS country,
  cb.city_name AS city,
  t10.payment_month AS month,
  ROUND(t10.month_total_amount, 2) AS month_total_amount,
  t10.payment_count,
  ROUND(t10.month_total_amount - ca.avg_monthly_amount_2005, 2) AS deviation_from_personal_avg,
  RANK() OVER (
    PARTITION BY cb.country_id, t10.payment_month
    ORDER BY t10.month_total_amount DESC
  ) AS customer_rank_within_country_month,
  st.o02 || ' ' || st.o03 AS top_staff_name,
  t10.country_month_customer_count AS customers_in_country_month
FROM top10pct_country_month t10
JOIN customer_base cb
  ON cb.customer_id = t10.customer_id
JOIN customer_avg ca
  ON ca.customer_id = t10.customer_id
JOIN top_staff_in_month ts
  ON ts.customer_id = t10.customer_id
 AND ts.payment_month = t10.payment_month
JOIN stf st
  ON st.o01 = ts.staff_id
WHERE ca.avg_monthly_amount_2005 IS NOT NULL
  AND ca.avg_monthly_amount_2005 > 0
  AND t10.month_total_amount > 2.0 * ca.avg_monthly_amount_2005
  AND t10.country_month_payment_rank <= (
      CAST(t10.country_month_customer_count * 0.10 AS INTEGER) +
      CASE
        WHEN t10.country_month_customer_count * 0.10 > CAST(t10.country_month_customer_count * 0.10 AS INTEGER)
        THEN 1 ELSE 0
      END
  )
ORDER BY
  cb.country_name,
  t10.payment_month,
  customer_rank_within_country_month,
  t10.month_total_amount DESC,
  cb.customer_id;