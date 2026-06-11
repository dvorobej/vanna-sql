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
customer_totals AS (
  SELECT
    customer_id,
    COUNT(p01) AS payment_count,
    SUM(amount) AS total_amount,
    AVG(amount) AS avg_check,
    SUM(CASE WHEN amount > 5.00 THEN 1 ELSE 0 END) AS payments_above_5,
    SUM(CASE WHEN amount > 5.00 THEN 1 ELSE 0 END) * 1.0 / COUNT(p01) AS share_payments_above_5
  FROM june_payments
  GROUP BY customer_id
)
SELECT
  c.h01 AS customer_id,
  c.h03 AS customer_first_name,
  c.h04 AS customer_last_name,
  ct.payment_count,
  ROUND(ct.total_amount, 2) AS total_amount,
  ROUND(ct.avg_check, 2) AS avg_check,
  ROUND(ct.share_payments_above_5, 4) AS share_payments_above_5,

  s.o01 AS staff_id,
  s.o02 AS staff_first_name,
  s.o03 AS staff_last_name,
  COUNT(jp.p01) AS staff_payment_count,
  SUM(jp.amount) AS staff_total_amount,
  ROUND(AVG(jp.amount), 2) AS staff_avg_check,
  SUM(CASE WHEN jp.amount > 5.00 THEN 1 ELSE 0 END) AS staff_payments_above_5
FROM june_payments AS jp
JOIN customer_totals AS ct
  ON ct.customer_id = jp.customer_id
JOIN cus AS c
  ON c.h01 = jp.customer_id
JOIN stf AS s
  ON s.o01 = jp.staff_id
WHERE ct.payment_count >= 5
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  ct.payment_count,
  ct.total_amount,
  ct.avg_check,
  ct.share_payments_above_5,
  s.o01,
  s.o02,
  s.o03
ORDER BY
  ct.total_amount DESC,
  staff_total_amount DESC,
  customer_id,
  staff_id;