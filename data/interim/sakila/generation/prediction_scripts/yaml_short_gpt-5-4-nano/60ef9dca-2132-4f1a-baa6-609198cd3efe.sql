WITH monthly AS (
  SELECT
    p.p02 AS customer_id,
    c.h02 AS store_id,
    strftime('%Y-%m', p.p06) AS month_key,
    strftime('%Y-%m', p.p06) || '-01' AS month_start,
    COUNT(p.p01) AS payment_count,
    SUM(p.p05) AS month_amount
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
cust_avg AS (
  SELECT
    customer_id,
    store_id,
    AVG(month_amount) AS avg_month_amount
  FROM monthly
  GROUP BY customer_id, store_id
),
monthly_scored AS (
  SELECT
    m.*,
    a.avg_month_amount,
    (m.month_amount - a.avg_month_amount) AS diff_from_avg,
    (m.month_amount / NULLIF(a.avg_month_amount, 0)) AS ratio_to_avg
  FROM monthly m
  JOIN cust_avg a
    ON a.customer_id = m.customer_id
   AND a.store_id = m.store_id
),
store_top_pct AS (
  SELECT
    ms.*,
    PERCENT_RANK() OVER (
      PARTITION BY ms.store_id
      ORDER BY ms.month_amount DESC
    ) AS pr_store_month
  FROM monthly_scored ms
),
last_staff AS (
  SELECT
    p.p02 AS customer_id,
    c.h02 AS store_id,
    p.p03 AS last_staff_id
  FROM pay p
  JOIN cus c
    ON c.h01 = p.p02
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY p.p02, c.h02
    ORDER BY p.p06 DESC, p.p01 DESC
  ) = 1
),
geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    cn.c02 AS country,
    ct.d02 AS city
  FROM cus c
  JOIN adr a
    ON a.e01 = c.h06
  JOIN cty ct
    ON ct.d01 = a.e05
  JOIN cnt cn
    ON cn.c01 = ct.d03
)
SELECT
  ss.customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  ss.store_id,
  g.city,
  g.country,
  strftime('%m', ss.month_start) AS month,
  ROUND(ss.month_amount, 2) AS month_sum,
  ss.payment_count,
  ROUND(ss.diff_from_avg, 2) AS deviation_from_avg,
  ss.pr_store_month,
  ls.last_staff_id
FROM store_top_pct ss
JOIN cus c
  ON c.h01 = ss.customer_id
 AND c.h02 = ss.store_id
JOIN geo g
  ON g.customer_id = ss.customer_id
 AND g.store_id = ss.store_id
LEFT JOIN last_staff ls
  ON ls.customer_id = ss.customer_id
 AND ls.store_id = ss.store_id
WHERE ss.ratio_to_avg > 2
  AND ss.pr_store_month <= 0.05
ORDER BY ss.store_id, ss.month_start, ss.month_amount DESC, ss.customer_id;