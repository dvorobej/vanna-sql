WITH month_pay AS (
  SELECT
    p.p02 AS customer_id,
    cu.h02 AS store_id,
    cu.h01 AS customer_key,
    cty.d02 AS city_name,
    cnty.c02 AS country_name,
    strftime('%Y-%m', p.p06) AS month_ym,
    date(p.p06, 'start of month') AS month_start,
    COUNT(p.p01) AS payment_count,
    SUM(p.p05) AS month_amount
  FROM pay AS p
  JOIN cus AS cu
    ON cu.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = cu.h06
  JOIN cty AS cty
    ON cty.d01 = a.e05
  JOIN cnt AS cnty
    ON cnty.c01 = cty.d03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    p.p02,
    cu.h02,
    cty.d02,
    cnty.c02,
    strftime('%Y-%m', p.p06),
    date(p.p06, 'start of month')
),
customer_year_avg AS (
  SELECT
    customer_id,
    AVG(month_amount) AS personal_avg_month_amount
  FROM month_pay
  GROUP BY customer_id
),
store_month_rank AS (
  SELECT
    mp.*,
    cya.personal_avg_month_amount,
    (mp.month_amount - cya.personal_avg_month_amount) AS deviation_from_personal_avg,
    RANK() OVER (
      PARTITION BY mp.store_id, mp.month_start
      ORDER BY mp.month_amount DESC
    ) AS store_month_amount_rank,
    COUNT(*) OVER (
      PARTITION BY mp.store_id, mp.month_start
    ) AS store_month_customer_count
  FROM month_pay AS mp
  JOIN customer_year_avg AS cya
    ON cya.customer_id = mp.customer_id
),
qualified_months AS (
  SELECT
    smr.*
  FROM store_month_rank AS smr
  WHERE
    smr.month_amount > smr.personal_avg_month_amount * 2
    AND smr.store_month_rank <= CAST((smr.store_month_customer_count * 0.05) AS INT)
),
candidate_customers AS (
  SELECT
    customer_id,
    store_id,
    city_name,
    country_name
  FROM qualified_months
  GROUP BY customer_id, store_id, city_name, country_name
  HAVING COUNT(DISTINCT month_start) = 12
)
SELECT
  cm.customer_id,
  cm.store_id AS store_id,
  cm.city_name,
  cm.country_name,
  q.month_ym AS month,
  ROUND(q.month_amount, 2) AS month_amount,
  q.payment_count,
  ROUND(q.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
  q.store_month_amount_rank AS store_month_rank,
  last_stf.staff_id AS last_staff_id,
  last_stf.o02 AS last_staff_first_name,
  last_stf.o03 AS last_staff_last_name
FROM candidate_customers AS cm
JOIN qualified_months AS q
  ON q.customer_id = cm.customer_id
 AND q.store_id = cm.store_id
 AND q.city_name = cm.city_name
 AND q.country_name = cm.country_name
LEFT JOIN (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    p.p03 AS staff_id
  FROM pay AS p
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY p.p02, date(p.p06, 'start of month')
    ORDER BY p.p06 DESC, p.p01 DESC
  ) = 1
) AS lp
  ON lp.customer_id = q.customer_id
 AND lp.month_start = q.month_start
LEFT JOIN stf AS last_stf
  ON last_stf.o01 = lp.staff_id
ORDER BY
  q.month_start,
  q.store_id,
  q.store_month_amount_rank,
  q.customer_id;