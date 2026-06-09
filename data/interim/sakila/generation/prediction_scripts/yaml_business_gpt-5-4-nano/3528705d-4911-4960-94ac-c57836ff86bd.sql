WITH eligible AS (
  SELECT
    p.p02 AS customer_id
  FROM pay AS p
  WHERE p.p06 >= '2005-06-01'
    AND p.p06 < '2005-07-01'
  GROUP BY p.p02
  HAVING SUM(p.p05) > 50.00
)
SELECT
  c.h01 AS customer_id,
  c.h03 AS customer_first_name,
  c.h04 AS customer_last_name,
  s.o01 AS staff_id,
  s.o02 AS staff_first_name,
  s.o03 AS staff_last_name,
  COUNT(p.p01) AS payment_count,
  ROUND(SUM(p.p05), 2) AS total_amount,
  ROUND(AVG(p.p05), 2) AS average_payment,
  ROUND(
    1.0 * SUM(CASE WHEN e2.total_amount > 0 THEN 0 ELSE 0 END),
    0
  ) AS dummy
FROM pay AS p
JOIN eligible AS e ON e.customer_id = p.p02
JOIN cus AS c ON c.h01 = p.p02
JOIN stf AS s ON s.o01 = p.p03
LEFT JOIN (
  SELECT
    p2.p02 AS customer_id,
    SUM(p2.p05) AS total_amount
  FROM pay AS p2
  WHERE p2.p06 >= '2005-06-01'
    AND p2.p06 < '2005-07-01'
  GROUP BY p2.p02
) AS e2
  ON e2.customer_id = p.p02
WHERE p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  s.o01,
  s.o02,
  s.o03
ORDER BY total_amount DESC, payment_count DESC, customer_id, staff_id;