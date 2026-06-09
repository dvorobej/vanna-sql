WITH monthly AS (
  SELECT
    p.p02 AS customer_id,
    cu.h02 AS store_id,
    p.p06 AS payment_date,
    date(p.p06, 'start of month') AS month_start,
    COUNT(p.p01) AS payment_count,
    SUM(p.p05) AS payment_sum
  FROM pay AS p
  JOIN cus AS cu
    ON cu.h01 = p.p02
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    p.p02,
    cu.h02,
    date(p.p06, 'start of month')
),
cust_avg AS (
  SELECT
    customer_id,
    store_id,
    AVG(payment_sum) AS personal_avg_monthly_sum
  FROM monthly
  GROUP BY customer_id, store_id
),
monthly_with_rank AS (
  SELECT
    m.customer_id,
    m.store_id,
    m.month_start,
    m.payment_count,
    m.payment_sum,
    ca.personal_avg_monthly_sum,
    (m.payment_sum - ca.personal_avg_monthly_sum) AS deviation_from_personal_avg,
    PERCENT_RANK() OVER (
      PARTITION BY m.store_id, m.month_start
      ORDER BY m.payment_sum DESC
    ) AS pct_rank_in_store
  FROM monthly AS m
  JOIN cust_avg AS ca
    ON ca.customer_id = m.customer_id
   AND ca.store_id = m.store_id
),
qual_months AS (
  SELECT
    *
  FROM monthly_with_rank
  WHERE payment_sum > personal_avg_monthly_sum * 2
    AND pct_rank_in_store <= 0.05
),
cust_complete AS (
  SELECT
    customer_id,
    store_id,
    COUNT(*) AS qualified_months_count
  FROM qual_months
  GROUP BY customer_id, store_id
  HAVING COUNT(*) = 12
),
staff_month AS (
  SELECT
    p.p02 AS customer_id,
    cu.h02 AS store_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, cu.h02, date(p.p06, 'start of month')
      ORDER BY p.p05 DESC, p.p01 DESC
    ) AS rn
  FROM pay AS p
  JOIN cus AS cu
    ON cu.h01 = p.p02
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
),
staff_last AS (
  SELECT
    customer_id,
    store_id,
    month_start,
    staff_id
  FROM staff_month
  WHERE rn = 1
),
geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    cnt.c02 AS country_name,
    city.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS city
    ON city.d01 = a.e05
  JOIN cnt AS cnt
    ON cnt.c01 = city.d03
)
SELECT
  q.customer_id,
  q.store_id AS store_id,
  g.city_name AS city,
  g.country_name AS country,
  strftime('%Y-%m', q.month_start) AS month,
  ROUND(q.payment_sum, 2) AS payment_sum,
  q.payment_count,
  ROUND(q.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
  DENSE_RANK() OVER (
    PARTITION BY q.store_id, q.month_start
    ORDER BY q.payment_sum DESC
  ) AS rank_in_store_by_month,
  sl.staff_id AS last_staff_id
FROM qual_months AS q
JOIN cust_complete AS cc
  ON cc.customer_id = q.customer_id
 AND cc.store_id = q.store_id
JOIN geo AS g
  ON g.customer_id = q.customer_id
 AND g.store_id = q.store_id
JOIN staff_last AS sl
  ON sl.customer_id = q.customer_id
 AND sl.store_id = q.store_id
 AND sl.month_start = q.month_start
ORDER BY
  q.store_id,
  q.month_start,
  q.customer_id;