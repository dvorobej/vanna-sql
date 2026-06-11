WITH monthly_pay AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS payment_amount_sum,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT COALESCE(r.q03, -1)) AS distinct_inventory_count
  FROM pay p
  JOIN ren r
    ON r.q01 = p.p04
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06, 'start of month')
),
monthly_with_prev AS (
  SELECT
    mp.*,
    AVG(mp.payment_amount_sum) OVER (
      PARTITION BY mp.customer_id
      ORDER BY mp.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS personal_avg_prev_amount
  FROM monthly_pay mp
),
monthly_flags AS (
  SELECT
    mwp.*,
    CASE
      WHEN mwp.personal_avg_prev_amount IS NOT NULL
       AND mwp.payment_amount_sum >= 2.0 * mwp.personal_avg_prev_amount
      THEN 1 ELSE 0
    END AS is_above_2x_prev_avg,
    CASE
      WHEN mwp.distinct_staff_count >= 2
        OR mwp.distinct_inventory_count >= 2
      THEN 1 ELSE 0
    END AS has_staff_or_store_variation
  FROM monthly_with_prev mwp
),
satisfied_customers AS (
  SELECT
    customer_id,
    COUNT(*) AS months_in_2005,
    SUM(is_above_2x_prev_avg) AS months_meeting_rule
  FROM monthly_flags
  WHERE payment_count >= 5
    AND has_staff_or_store_variation = 1
  GROUP BY customer_id
)
SELECT
  mf.month_start,
  mf.customer_id,
  c.h03 AS customer_first_name,
  c.h04 AS customer_last_name,
  cn.c02 AS country_name,
  ct.d02 AS city_name,
  ROUND(mf.payment_amount_sum, 2) AS month_payment_sum,
  mf.payment_count,
  ROUND(mf.payment_amount_sum - mf.personal_avg_prev_amount, 2) AS deviation_from_prev_avg,
  RANK() OVER (
    PARTITION BY c.h01, mf.month_start
    ORDER BY (mf.payment_amount_sum - mf.personal_avg_prev_amount) DESC
  ) AS customer_deviation_rank_in_country
FROM monthly_flags mf
JOIN cus c
  ON c.h01 = mf.customer_id
JOIN adr a
  ON a.e01 = c.h06
JOIN cty ct
  ON ct.d01 = a.e05
JOIN cnt cn
  ON cn.c01 = ct.d03
JOIN satisfied_customers sc
  ON sc.customer_id = mf.customer_id
WHERE mf.payment_count >= 5
  AND mf.has_staff_or_store_variation = 1
  AND mf.personal_avg_prev_amount IS NOT NULL
  AND mf.is_above_2x_prev_avg = 1
  AND mf.customer_id IN (
    SELECT customer_id
    FROM satisfied_customers
    WHERE months_meeting_rule = months_in_2005 - 1
  )
ORDER BY
  mf.month_start,
  cn.c02,
  customer_deviation_rank_in_country,
  mf.customer_id;