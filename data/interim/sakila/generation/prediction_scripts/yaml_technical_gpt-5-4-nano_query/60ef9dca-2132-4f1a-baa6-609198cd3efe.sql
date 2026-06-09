WITH payments_2005 AS (
  SELECT
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p04 AS rental_id,
    p.p05 AS payment_amount,
    date(p.p06, 'start of month') AS month_start,
    strftime('%Y-%m', p.p06) AS month_key
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS store_id,
    ct.d02 AS city_name,
    co.c02 AS country_name
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ct.d03
),
customer_month AS (
  SELECT
    p.customer_id,
    cg.store_id,
    cg.city_name,
    cg.country_name,
    p.month_start,
    p.month_key,
    COUNT(*) AS payment_count,
    SUM(p.payment_amount) AS month_sum
  FROM payments_2005 AS p
  JOIN customer_geo AS cg
    ON cg.customer_id = p.customer_id
  GROUP BY
    p.customer_id,
    cg.store_id,
    cg.city_name,
    cg.country_name,
    p.month_start,
    p.month_key
),
customer_year_avg AS (
  SELECT
    customer_id,
    store_id,
    AVG(month_sum) AS personal_avg_month_sum
  FROM customer_month
  GROUP BY customer_id, store_id
),
store_month_ranked AS (
  SELECT
    cm.*,
    cya.personal_avg_month_sum,
    RANK() OVER (
      PARTITION BY cm.store_id, cm.month_start
      ORDER BY cm.month_sum DESC
    ) AS store_month_rank,
    COUNT(*) OVER (
      PARTITION BY cm.store_id, cm.month_start
    ) AS store_month_customer_count
  FROM customer_month AS cm
  JOIN customer_year_avg AS cya
    ON cya.customer_id = cm.customer_id
   AND cya.store_id = cm.store_id
),
candidate_months AS (
  SELECT
    smr.*
  FROM store_month_ranked AS smr
  WHERE
    smr.month_sum > smr.personal_avg_month_sum * 2
    AND smr.store_month_rank <= (
      CAST( (smr.store_month_customer_count + 19) / 20 AS INT)
    )
),
months_count AS (
  SELECT
    customer_id,
    store_id,
    COUNT(*) AS good_months_count
  FROM candidate_months
  GROUP BY customer_id, store_id
),
all_months AS (
  SELECT
    COUNT(*) AS total_months
  FROM (
    SELECT DISTINCT month_start
    FROM payments_2005
  )
),
top_staff_last AS (
  SELECT
    p.customer_id,
    p.month_start,
    p.staff_id,
    ROW_NUMBER() OVER (
      PARTITION BY p.customer_id, p.month_start
      ORDER BY p.payment_amount DESC, p.staff_id
    ) AS rn_by_max_amount
  FROM payments_2005 AS p
),
last_staff_by_date AS (
  SELECT
    p.customer_id,
    p.month_start,
    p.staff_id,
    ROW_NUMBER() OVER (
      PARTITION BY p.customer_id, p.month_start
      ORDER BY p.month_start, p.staff_id, p.rental_id, p.payment_amount DESC
    ) AS rn
  FROM payments_2005 AS p
)
SELECT
  cm.customer_id,
  cm.store_id AS store_id,
  cm.city_name,
  cm.country_name,
  cm.month_key AS month,
  ROUND(cm.month_sum, 2) AS month_sum,
  cm.payment_count,
  ROUND(cm.month_sum - cm.personal_avg_month_sum, 2) AS deviation_from_personal_avg,
  cm.store_month_rank AS store_month_rank,
  (
    SELECT p2.staff_id
    FROM pay AS p2
    WHERE p2.p02 = cm.customer_id
      AND date(p2.p06, 'start of month') = cm.month_start
    ORDER BY p2.p06 DESC
    LIMIT 1
  ) AS last_staff_id
FROM store_month_ranked AS cm
JOIN months_count AS mc
  ON mc.customer_id = cm.customer_id
 AND mc.store_id = cm.store_id
JOIN all_months AS am
WHERE mc.good_months_count = am.total_months
  AND cm.month_sum > cm.personal_avg_month_sum * 2
  AND cm.store_month_rank <= (
      CAST( (cm.store_month_customer_count + 19) / 20 AS INT)
    )
ORDER BY
  cm.customer_id,
  cm.month_start;