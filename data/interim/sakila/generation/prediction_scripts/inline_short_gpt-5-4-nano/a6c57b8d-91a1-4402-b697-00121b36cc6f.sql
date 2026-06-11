WITH monthly_customer AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cn.c01 AS country_id,
    cn.c02 AS country_name,
    ct.d02 AS city_name,
    strftime('%Y-%m', p.p06) AS payment_month,
    SUM(p.p05) AS month_amount,
    COUNT(p.p01) AS month_payment_count,
    MAX(p.p03) FILTER (WHERE p.p03 IS NOT NULL) AS dummy
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS cn
    ON cn.c01 = ct.d03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    c.h01,
    c.h03,
    c.h04,
    cn.c01,
    cn.c02,
    ct.d02,
    strftime('%Y-%m', p.p06)
),
monthly_with_averages AS (
  SELECT
    mc.*,
    AVG(mc.month_amount) OVER (
      PARTITION BY mc.customer_id
    ) AS customer_avg_month_amount,
    AVG(mc.month_payment_count * 1.0) OVER (
      PARTITION BY mc.customer_id
    ) AS customer_avg_month_payment_count,
    AVG(mc.month_amount) OVER (
      PARTITION BY mc.country_id, mc.payment_month
    ) AS country_avg_month_amount,
    AVG(mc.month_payment_count * 1.0) OVER (
      PARTITION BY mc.country_id, mc.payment_month
    ) AS country_avg_month_payment_count
  FROM monthly_customer AS mc
),
ranked_last_staff AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS payment_month,
    p.p03 AS staff_id,
    p.p05 AS payment_amount,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, strftime('%Y-%m', p.p06)
      ORDER BY p.p05 DESC, p.p01 DESC
    ) AS rn
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
),
top_staff_by_month AS (
  SELECT
    customer_id,
    payment_month,
    staff_id
  FROM ranked_last_staff
  WHERE rn = 1
),
final_rows AS (
  SELECT
    mwa.customer_id,
    mwa.first_name,
    mwa.last_name,
    mwa.country_id,
    mwa.country_name,
    mwa.city_name,
    mwa.payment_month,
    mwa.month_amount,
    mwa.month_payment_count,
    (mwa.month_amount - mwa.customer_avg_month_amount) AS deviation_from_personal_avg_amount,
    (mwa.month_payment_count - mwa.customer_avg_month_payment_count) AS deviation_from_personal_avg_count,
    (mwa.month_amount - mwa.country_avg_month_amount) AS deviation_from_country_avg_amount,
    (mwa.month_payment_count - mwa.country_avg_month_payment_count) AS deviation_from_country_avg_count,
    RANK() OVER (
      PARTITION BY mwa.country_id, mwa.payment_month
      ORDER BY mwa.month_amount - mwa.country_avg_month_amount DESC
    ) AS amount_deviation_rank
  FROM monthly_with_averages AS mwa
)
SELECT
  fr.customer_id,
  fr.first_name,
  fr.last_name,
  fr.country_name,
  fr.city_name,
  fr.payment_month,
  ROUND(fr.month_amount, 2) AS month_payment_amount,
  fr.month_payment_count,
  ROUND(fr.deviation_from_personal_avg_amount, 2) AS deviation_from_personal_avg_amount,
  ROUND(fr.deviation_from_country_avg_amount, 2) AS deviation_from_country_avg_amount,
  fr.amount_deviation_rank,
  st.o01 AS staff_id,
  st.o02 || ' ' || st.o03 AS staff_name
FROM final_rows AS fr
LEFT JOIN top_staff_by_month AS ts
  ON ts.customer_id = fr.customer_id
 AND ts.payment_month = fr.payment_month
LEFT JOIN stf AS st
  ON st.o01 = ts.staff_id
ORDER BY
  fr.country_name,
  fr.payment_month,
  fr.amount_deviation_rank,
  fr.customer_id;