WITH monthly_pay AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS month_sum
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
customer_month_stats AS (
  SELECT
    mp.customer_id,
    mp.month_start,
    mp.payment_count,
    mp.month_sum,
    AVG(mp.month_sum) OVER (PARTITION BY mp.customer_id) AS personal_avg_month_sum,
    (mp.month_sum / NULLIF(AVG(mp.month_sum) OVER (PARTITION BY mp.customer_id), 0.0)) AS personal_vs_avg_ratio,
    RANK() OVER (
      PARTITION BY c.h02, mp.month_start
      ORDER BY mp.month_sum DESC
    ) AS store_month_sum_rank,
    COUNT(*) OVER (
      PARTITION BY c.h02, mp.month_start
    ) AS store_month_customer_count
  FROM monthly_pay AS mp
  JOIN cus AS c
    ON c.h01 = mp.customer_id
),
store_pivot AS (
  SELECT
    customer_id,
    month_start,
    payment_count,
    month_sum,
    personal_avg_month_sum,
    personal_vs_avg_ratio,
    store_month_sum_rank,
    store_month_customer_count,
    CASE
      WHEN (store_month_customer_count * 0.05) < 1 THEN 1
      ELSE CAST(store_month_customer_count * 0.05 AS INTEGER)
    END AS top5_count
  FROM customer_month_stats
),
qualified_months AS (
  SELECT *
  FROM store_pivot
  WHERE personal_vs_avg_ratio > 2.0
    AND store_month_sum_rank <= top5_count
),
months_2005 AS (
  SELECT date('2005-01-01', printf('+%d months', n.n)) AS month_start
  FROM (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL
        SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL
        SELECT 10 UNION ALL SELECT 11) AS n
),
qualified_customers_all_months AS (
  SELECT
    qm.customer_id
  FROM qualified_months AS qm
  JOIN months_2005 AS m
    ON m.month_start = qm.month_start
  GROUP BY qm.customer_id
  HAVING COUNT(DISTINCT qm.month_start) = 12
),
last_staff_per_month AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS last_staff_id
  FROM (
    SELECT
      p.*,
      ROW_NUMBER() OVER (
        PARTITION BY p.p02, date(p.p06, 'start of month')
        ORDER BY p.p06 DESC, p.p01 DESC
      ) AS rn
    FROM pay AS p
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 <  '2006-01-01'
  ) AS p
  WHERE p.rn = 1
),
final_data AS (
  SELECT
    c.h01 AS customer_id,
    c.h03,
    c.h04,
    c.h02 AS store_id,
    cnt.c02 AS country,
    ct.d02 AS city,
    qs.month_start,
    qs.payment_count,
    qs.month_sum,
    qs.personal_avg_month_sum,
    (qs.month_sum - qs.personal_avg_month_sum) AS deviation_from_personal_avg,
    qs.store_month_sum_rank,
    qs.store_month_customer_count,
    ls.last_staff_id
  FROM qualified_customers_all_months AS qca
  JOIN qualified_months AS qs
    ON qs.customer_id = qca.customer_id
  JOIN cus AS c
    ON c.h01 = qs.customer_id
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS cnt
    ON cnt.c01 = ct.d03
  JOIN last_staff_per_month AS ls
    ON ls.customer_id = qs.customer_id
   AND ls.month_start = qs.month_start
)
SELECT
  customer_id AS h01,
  h03 || ' ' || h04 AS customer_name,
  store_id AS h02,
  country,
  city,
  month_start AS month,
  payment_count,
  ROUND(month_sum, 2) AS month_sum,
  ROUND(personal_avg_month_sum, 2) AS personal_avg_month_sum,
  ROUND(deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
  store_month_sum_rank AS store_month_rank,
  store_month_customer_count,
  last_staff_id AS last_staff_o01
FROM final_data
ORDER BY
  country,
  month_start,
  store_id,
  month_sum DESC,
  customer_id;