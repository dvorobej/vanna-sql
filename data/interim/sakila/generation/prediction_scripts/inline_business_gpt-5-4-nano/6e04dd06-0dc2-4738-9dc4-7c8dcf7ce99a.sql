WITH
monthly_payments AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS payment_month,
    SUM(p.p05) AS month_payment_sum,
    COUNT(p.p01) AS month_payment_count
  FROM pay AS p
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06)
),
monthly_geo AS (
  SELECT
    c.h01 AS customer_id,
    ct.c02 AS country_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt AS ct ON ct.c01 = ci.d03
  WHERE c.h07 IN ('1', 'Y')
),
monthly_staff_store AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS payment_month,
    GROUP_CONCAT(DISTINCT (s.o02 || ' ' || s.o03) || ' (id=' || s.o01 || ')') AS staff_list,
    GROUP_CONCAT(DISTINCT st.j01) AS store_list
  FROM pay AS p
  JOIN stf AS s ON s.o01 = p.p03
  JOIN sto AS st ON st.j01 = s.o07
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06)
),
prepared AS (
  SELECT
    mp.customer_id,
    mp.payment_month,
    mp.month_payment_sum,
    mp.month_payment_count,
    mg.country_name,
    mss.staff_list,
    mss.store_list,
    LAG(mp.month_payment_sum, 1) OVER (PARTITION BY mp.customer_id ORDER BY mp.payment_month) AS prev1_sum,
    LAG(mp.month_payment_sum, 2) OVER (PARTITION BY mp.customer_id ORDER BY mp.payment_month) AS prev2_sum,
    LAG(mp.month_payment_sum, 3) OVER (PARTITION BY mp.customer_id ORDER BY mp.payment_month) AS prev3_sum
  FROM monthly_payments AS mp
  JOIN monthly_geo AS mg ON mg.customer_id = mp.customer_id
  LEFT JOIN monthly_staff_store AS mss
    ON mss.customer_id = mp.customer_id
   AND mss.payment_month = mp.payment_month
),
country_month_stats AS (
  SELECT
    country_name,
    payment_month,
    month_payment_sum,
    COUNT(*) OVER (PARTITION BY country_name, payment_month) AS cnt_in_group,
    ROW_NUMBER() OVER (
      PARTITION BY country_name, payment_month
      ORDER BY month_payment_sum
    ) AS rn_asc
  FROM prepared
),
country_month_median AS (
  SELECT
    cms.country_name,
    cms.payment_month,
    AVG(cms.month_payment_sum * 1.0) AS country_median_payment_sum
  FROM country_month_stats AS cms
  WHERE cms.rn_asc IN (
    CAST((cms.cnt_in_group + 1) / 2 AS INTEGER),
    CAST((cms.cnt_in_group + 2) / 2 AS INTEGER)
  )
  GROUP BY
    cms.country_name,
    cms.payment_month
),
final_ranked AS (
  SELECT
    p.*,
    cmm.country_median_payment_sum,
    NTILE(20) OVER (
      PARTITION BY p.country_name, p.payment_month
      ORDER BY p.month_payment_sum DESC
    ) AS tile20_desc
  FROM prepared AS p
  JOIN country_month_median AS cmm
    ON cmm.country_name = p.country_name
   AND cmm.payment_month = p.payment_month
)
SELECT
  fr.customer_id,
  cus.h03 AS first_name,
  cus.h04 AS last_name,
  fr.country_name,
  fr.payment_month,
  fr.month_payment_count,
  ROUND(fr.month_payment_sum, 2) AS month_payment_sum,
  fr.staff_list,
  fr.store_list,
  ROUND(((fr.month_payment_sum * 1.0) / NULLIF(((fr.prev1_sum + fr.prev2_sum + fr.prev3_sum) / 3.0), 0)), 2) AS ratio_to_own_3mo_avg,
  ROUND(fr.country_median_payment_sum, 2) AS country_median_payment_sum,
  ROUND((fr.month_payment_sum * 1.0) / NULLIF(fr.country_median_payment_sum, 0), 2) AS ratio_to_country_median
FROM final_ranked AS fr
JOIN cus
  ON cus.h01 = fr.customer_id
WHERE
  fr.prev1_sum IS NOT NULL
  AND fr.prev2_sum IS NOT NULL
  AND fr.prev3_sum IS NOT NULL
  AND fr.month_payment_sum >= 3.0 * ((fr.prev1_sum + fr.prev2_sum + fr.prev3_sum) / 3.0)
  AND fr.month_payment_sum >= 2.0 * fr.country_median_payment_sum
  AND fr.tile20_desc = 1
ORDER BY
  fr.country_name,
  fr.payment_month,
  fr.month_payment_sum DESC,
  fr.customer_id;