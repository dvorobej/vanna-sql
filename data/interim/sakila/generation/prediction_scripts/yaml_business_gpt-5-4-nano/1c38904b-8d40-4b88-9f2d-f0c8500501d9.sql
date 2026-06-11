WITH month_payments AS (
  SELECT
    p.p01,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p05 AS amount
  FROM pay AS p
  WHERE p.p06 >= '2005-06-01'
    AND p.p06 < '2005-07-01'
),
enriched AS (
  SELECT
    mp.customer_id,
    mp.staff_id,
    mp.p01 AS payment_id,
    mp.amount,
    c.h02 AS customer_store_id,
    s.o07 AS staff_store_id
  FROM month_payments mp
  JOIN cus c
    ON c.h01 = mp.customer_id
  JOIN stf s
    ON s.o01 = mp.staff_id
)
SELECT
  e.customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  COUNT(e.payment_id) AS payment_count,
  ROUND(SUM(e.amount), 2) AS total_amount,
  ROUND(AVG(e.amount), 2) AS average_payment_amount,
  ROUND(
    AVG(CASE WHEN e.amount > 5.00 THEN 1.0 ELSE 0.0 END),
    4
  ) AS share_operations_amount_gt_5,
  SUM(CASE WHEN e.staff_store_id <> e.customer_store_id THEN 1 ELSE 0 END) AS payments_from_other_store_count,
  ROUND(
    1.0 * SUM(CASE WHEN e.staff_store_id <> e.customer_store_id THEN 1 ELSE 0 END) / COUNT(e.payment_id),
    4
  ) AS share_payments_from_other_store
FROM enriched e
JOIN cus c
  ON c.h01 = e.customer_id
GROUP BY
  e.customer_id,
  c.h03,
  c.h04
HAVING COUNT(e.payment_id) > 5
   AND SUM(e.amount) > 30
ORDER BY
  total_amount DESC,
  payment_count DESC,
  e.customer_id;