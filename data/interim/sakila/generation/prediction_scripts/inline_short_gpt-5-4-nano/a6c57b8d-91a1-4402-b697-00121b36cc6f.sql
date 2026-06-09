SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  cn.c02 AS country,
  ct.d02 AS city,
  mp.payment_month,
  mp.month_amount,
  mp.month_payment_count,
  (mp.month_amount - cust_avg.month_avg_amount) AS amount_deviation_from_customer_avg,
  (mp.month_payment_count - cust_avg.month_avg_count) AS count_deviation_from_customer_avg,
  (mp.month_amount - country_avg.country_avg_amount) AS amount_deviation_from_country_avg,
  (mp.month_payment_count - country_avg.country_avg_count) AS count_deviation_from_country_avg,
  RANK() OVER (
    PARTITION BY cn.c01, mp.payment_month
    ORDER BY (mp.month_amount - country_avg.country_avg_amount) DESC
  ) AS country_rank,
  stf.o01 AS staff_id,
  stf.o02 || ' ' || stf.o03 AS staff_name_by_max_month_payment
FROM (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS payment_month,
    SUM(p.p05) AS month_amount,
    COUNT(*) AS month_payment_count,
    MAX(p.p05) AS max_payment_amount
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06)
) AS mp
JOIN cus AS c
  ON c.h01 = mp.customer_id
JOIN adr AS a
  ON a.e01 = c.h06
JOIN cty AS ct
  ON ct.d01 = a.e05
JOIN cnt AS cn
  ON cn.c01 = ct.d03
JOIN (
  SELECT
    p.p02 AS customer_id,
    AVG(SUM(p.p05)) OVER (PARTITION BY p.p02) AS month_avg_amount,
    AVG(COUNT(*)) OVER (PARTITION BY p.p02) AS month_avg_count
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06)
) AS cust_avg
  ON cust_avg.customer_id = mp.customer_id
JOIN (
  SELECT
    cn2.c01 AS country_id,
    strftime('%Y-%m', p2.p06) AS payment_month,
    AVG(month_amount) AS country_avg_amount,
    AVG(month_payment_count) AS country_avg_count
  FROM (
    SELECT
      p2.p02 AS customer_id,
      strftime('%Y-%m', p2.p06) AS payment_month,
      SUM(p2.p05) AS month_amount,
      COUNT(*) AS month_payment_count
    FROM pay AS p2
    WHERE p2.p06 >= '2005-01-01'
      AND p2.p06 < '2006-01-01'
    GROUP BY
      p2.p02,
      strftime('%Y-%m', p2.p06)
  ) AS m
  JOIN cus AS c2
    ON c2.h01 = m.customer_id
  JOIN adr AS a2
    ON a2.e01 = c2.h06
  JOIN cty AS ct2
    ON ct2.d01 = a2.e05
  JOIN cnt AS cn2
    ON cn2.c01 = ct2.d03
  GROUP BY
    cn2.c01,
    strftime('%Y-%m', p2.p06)
) AS country_avg
  ON country_avg.country_id = cn.c01
 AND country_avg.payment_month = mp.payment_month
LEFT JOIN (
  SELECT
    p3.p02 AS customer_id,
    strftime('%Y-%m', p3.p06) AS payment_month,
    p3.p03 AS staff_id,
    p4.p05 AS max_staff_payment_amount
  FROM pay AS p3
  JOIN (
    SELECT
      p2.p02 AS customer_id,
      strftime('%Y-%m', p2.p06) AS payment_month,
      MAX(p2.p05) AS max_staff_payment_amount
    FROM pay AS p2
    WHERE p2.p06 >= '2005-01-01'
      AND p2.p06 < '2006-01-01'
    GROUP BY
      p2.p02,
      strftime('%Y-%m', p2.p06)
  ) AS p4m
    ON p4m.customer_id = p3.p02
   AND p4m.payment_month = strftime('%Y-%m', p3.p06)
   AND p4m.max_staff_payment_amount = p3.p05
) AS max_staff
  ON max_staff.customer_id = mp.customer_id
 AND max_staff.payment_month = mp.payment_month
LEFT JOIN stf AS stf
  ON stf.o01 = max_staff.staff_id
ORDER BY
  cn.c02,
  mp.payment_month,
  country_rank,
  mp.customer_id;