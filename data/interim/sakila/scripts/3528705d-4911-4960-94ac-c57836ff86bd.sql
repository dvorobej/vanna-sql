WITH june_payments AS (
  SELECT
    p.p01,
    p.p02,
    p.p03,
    p.p05
  FROM pay AS p
  WHERE p.p06 >= '2005-06-01'
    AND p.p06 < '2005-07-01'
),
qualified_customers AS (
  SELECT
    p02
  FROM june_payments
  GROUP BY p02
  HAVING SUM(p05) > 50
)
SELECT
  c.h01 AS customer_id,
  c.h03 AS customer_first_name,
  c.h04 AS customer_last_name,
  s.o01 AS staff_id,
  s.o02 AS staff_first_name,
  s.o03 AS staff_last_name,
  COUNT(jp.p01) AS payment_count,
  ROUND(SUM(jp.p05), 2) AS total_amount,
  ROUND(AVG(jp.p05), 2) AS average_check,
  ROUND(
    CAST(COUNT(jp.p01) AS REAL)
    / SUM(COUNT(jp.p01)) OVER (PARTITION BY c.h01),
    4
  ) AS staff_operation_share
FROM june_payments AS jp
JOIN qualified_customers AS qc
  ON qc.p02 = jp.p02
JOIN cus AS c
  ON c.h01 = jp.p02
JOIN stf AS s
  ON s.o01 = jp.p03
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  s.o01,
  s.o02,
  s.o03
ORDER BY
  c.h01,
  staff_operation_share DESC,
  s.o01;