WITH june_payments AS (
  SELECT *
  FROM pay
  WHERE p06 >= '2005-06-01'
    AND p06 < '2005-07-01'
),
high_activity_customers AS (
  SELECT p02 AS customer_id
  FROM june_payments
  GROUP BY p02
  HAVING COUNT(p01) > 10
)
SELECT
  c.h01 AS customer_id,
  c.h03 || ' ' || c.h04 AS customer_name,
  s.o01 AS staff_id,
  s.o02 || ' ' || s.o03 AS staff_name,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  AVG(p.p05) AS average_payment,
  SUM(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) AS large_payment_count
FROM june_payments AS p
JOIN high_activity_customers AS hac
  ON hac.customer_id = p.p02
JOIN cus AS c
  ON c.h01 = p.p02
JOIN stf AS s
  ON s.o01 = p.p03
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  s.o01,
  s.o02,
  s.o03
ORDER BY
  total_amount DESC,
  payment_count DESC;