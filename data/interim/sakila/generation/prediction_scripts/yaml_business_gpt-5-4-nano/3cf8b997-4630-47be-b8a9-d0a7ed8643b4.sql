WITH monthly AS (
  SELECT
    c.h01 AS customer_id,
    strftime('%Y-%m', p.p06) AS month_start,
    c.h02 AS store_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    ci.d02 AS city,
    cn.d03 AS country_id,
    COUNT(p.p01) AS payment_count,
    SUM(p.p05) AS payment_sum,
    AVG(p.p05) AS avg_payment_amount
  FROM pay p
  JOIN cus c
    ON c.h01 = p.p02
  JOIN adr a
    ON a.e01 = c.h06
  JOIN cty ci
    ON ci.d01 = a.e05
  JOIN cnt cn
    ON cn.c01 = ci.d03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    c.h01, c.h02, strftime('%Y-%m', p.p06),
    c.h03, c.h04, ci.d02, cn.d03
),
monthly_with_prev AS (
  SELECT
    m.*,
    AVG(m.payment_sum) OVER (
      PARTITION BY m.customer_id
      ORDER BY m.month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS prev2_avg_payment_sum
  FROM monthly m
),
suspicious_months AS (
  SELECT
    mwp.*,
    CASE
      WHEN mwp.prev2_avg_payment_sum IS NOT NULL
       AND mwp.payment_sum >= 2.0 * mwp.prev2_avg_payment_sum
       AND mwp.payment_count >= 3
      THEN 1 ELSE 0
    END AS is_suspicious
  FROM monthly_with_prev mwp
),
store_month_quantiles AS (
  SELECT
    sm.month_start,
    sm.store_id,
    sm.customer_id,
    sm.payment_sum,
    sm.payment_count,
    PERCENT_RANK() OVER (
      PARTITION BY sm.store_id, sm.month_start
      ORDER BY sm.payment_sum
    ) AS pr
  FROM suspicious_months sm
  WHERE sm.is_suspicious = 1
),
qualified_suspicious AS (
  SELECT
    sm.*,
    DENSE_RANK() OVER (
      PARTITION BY sm.store_id
      ORDER BY sm.payment_sum DESC
    ) AS store_payment_rank
  FROM suspicious_months sm
  WHERE sm.is_suspicious = 1
),
customer_store_month_ranked AS (
  SELECT
    qs.*,
    LAG(qs.payment_sum) OVER (
      PARTITION BY qs.store_id, qs.customer_id
      ORDER BY qs.month_start
    ) AS dummy
  FROM qualified_suspicious qs
),
customer_year_suspicious_check AS (
  SELECT
    customer_id,
    store_id,
    MIN(CASE WHEN is_suspicious = 1 THEN 1 ELSE 0 END) AS all_months_suspicious,
    SUM(is_suspicious) AS suspicious_months_count
  FROM suspicious_months
  GROUP BY customer_id, store_id
),
final_customers AS (
  SELECT
    cys.customer_id,
    cys.store_id
  FROM customer_store_month_ranked cys
  JOIN customer_year_suspicious_check y
    ON y.customer_id = cys.customer_id
   AND y.store_id = cys.store_id
  WHERE y.all_months_suspicious = 1
)
, month_top_staff AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS month_start,
    p.p03 AS staff_id,
    SUM(p.p05) AS staff_payment_sum,
    ROW_NUMBER() OVER (
      PARTITION BY p.p02, strftime('%Y-%m', p.p06)
      ORDER BY SUM(p.p05) DESC
    ) AS rn
  FROM pay p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 < '2006-01-01'
  GROUP BY
    p.p02, strftime('%Y-%m', p.p06), p.p03
)
SELECT
  sm.month_start AS month,
  sm.customer_id,
  sm.first_name,
  sm.last_name,
  sm.store_id AS customer_store_id,
  sm.city,
  sm.country_id,
  sm.payment_sum,
  sm.payment_count,
  ROUND(sm.payment_sum - sm.prev2_avg_payment_sum, 2) AS deviation_from_moving_avg,
  RANK() OVER (
    PARTITION BY sm.store_id
    ORDER BY sm.payment_sum DESC
  ) AS store_rank_by_month_sum,
  mts.staff_id AS top_staff_id,
  ROUND(mts.staff_payment_sum, 2) AS top_staff_payment_sum
FROM suspicious_months sm
JOIN final_customers fc
  ON fc.customer_id = sm.customer_id
 AND fc.store_id = sm.store_id
LEFT JOIN month_top_staff mts
  ON mts.customer_id = sm.customer_id
 AND mts.month_start = sm.month_start
 AND mts.rn = 1
WHERE sm.is_suspicious = 1
  AND sm.payment_sum IS NOT NULL
  AND sm.prev2_avg_payment_sum IS NOT NULL
ORDER BY
  sm.store_id,
  sm.month_start,
  sm.payment_sum DESC;