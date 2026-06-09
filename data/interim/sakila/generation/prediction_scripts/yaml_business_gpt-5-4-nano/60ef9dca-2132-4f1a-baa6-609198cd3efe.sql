WITH monthly_customer AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS month_ym,
    SUM(CAST(p.p05 AS REAL)) AS month_amount,
    COUNT(*) AS payment_count,
    MAX(p.p06) AS last_payment_datetime,
    -- последний сотрудник, принявший платёж в месяце
    (SELECT p2.p03
     FROM pay AS p2
     WHERE p2.p02 = p.p02
       AND strftime('%Y-%m', p2.p06) = strftime('%Y-%m', p.p06)
     ORDER BY p2.p06 DESC
     LIMIT 1) AS last_staff_id
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06)
),
monthly_with_personal_avg AS (
  SELECT
    mc.*,
    AVG(mc.month_amount) OVER (PARTITION BY mc.customer_id) AS personal_avg_2005
  FROM monthly_customer AS mc
),
monthly_in_store AS (
  SELECT
    mpa.*,
    s.j01 AS store_id,
    RANK() OVER (
      PARTITION BY s.j01, mpa.month_ym
      ORDER BY mpa.month_amount DESC
    ) AS store_month_rank,
    COUNT(*) OVER (
      PARTITION BY s.j01, mpa.month_ym
    ) AS store_month_customer_count
  FROM monthly_with_personal_avg AS mpa
  JOIN cus AS c
    ON c.h01 = mpa.customer_id
  JOIN sto AS s
    ON s.j01 = c.h02
),
eligible_customers AS (
  -- оставляем только тех, у кого по каждому месяцу 2005 сумма >= 3 * личного среднего
  SELECT
    customer_id
  FROM monthly_in_store
  GROUP BY customer_id
  HAVING COUNT(*) = 12
     AND MIN(month_amount) >= 3 * MAX(personal_avg_2005)
)
SELECT
  mi.customer_id,
  c.h03 AS customer_first_name,
  c.h04 AS customer_last_name,
  mi.store_id,
  adr.e05 AS city_id,
  ct.d02 AS city_name,
  cn.c02 AS country_name,
  mi.month_ym AS month,
  ROUND(mi.month_amount, 2) AS month_amount,
  mi.payment_count,
  ROUND(mi.month_amount - mi.personal_avg_2005, 2) AS deviation_from_personal_avg,
  mi.last_staff_id AS last_staff_id,
  mi.store_month_rank AS position_in_store_month
FROM monthly_in_store AS mi
JOIN eligible_customers AS ec
  ON ec.customer_id = mi.customer_id
JOIN cus AS c
  ON c.h01 = mi.customer_id
JOIN adr
  ON adr.e01 = c.h06
JOIN cty AS ct
  ON ct.d01 = adr.e05
JOIN cnt AS cn
  ON cn.c01 = ct.d03
ORDER BY
  mi.month_ym,
  mi.store_id,
  mi.month_amount DESC,
  mi.customer_id;