WITH june_payments AS (
  SELECT
    p.p01,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p05 AS amount
  FROM pay AS p
  WHERE p.p06 >= '2005-06-01'
    AND p.p06 < '2005-07-01'
),
client_agg AS (
  SELECT
    jp.customer_id,
    COUNT(jp.p01) AS payment_count,
    SUM(jp.amount) AS total_amount,
    AVG(jp.amount) AS average_check,
    SUM(CASE WHEN jp.amount > 5.00 THEN 1 ELSE 0 END) AS payments_above_5_count
  FROM june_payments AS jp
  GROUP BY jp.customer_id
  HAVING COUNT(jp.p01) >= 5
)
SELECT
  c.h01 AS customer_id,
  c.h03 AS customer_first_name,
  c.h04 AS customer_last_name,
  s.o01 AS staff_id,
  s.o02 AS staff_first_name,
  s.o03 AS staff_last_name,
  ca.payment_count,
  ROUND(ca.total_amount, 2) AS total_amount,
  ROUND(ca.average_check, 2) AS average_check,
  ROUND(
    1.0 * ca.payments_above_5_count / ca.payment_count,
    4
  ) AS payments_above_5_share,
  COUNT(jp.p01) AS staff_payment_count,
  ROUND(SUM(jp.amount), 2) AS staff_total_amount
FROM client_agg AS ca
JOIN cus AS c
  ON c.h01 = ca.customer_id
JOIN june_payments AS jp
  ON jp.customer_id = ca.customer_id
JOIN stf AS s
  ON s.o01 = jp.staff_id
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  s.o01,
  s.o02,
  s.o03,
  ca.payment_count,
  ca.total_amount,
  ca.average_check,
  ca.payments_above_5_count
ORDER BY
  ca.total_amount DESC,
  staff_payment_count DESC,
  customer_id,
  staff_id;