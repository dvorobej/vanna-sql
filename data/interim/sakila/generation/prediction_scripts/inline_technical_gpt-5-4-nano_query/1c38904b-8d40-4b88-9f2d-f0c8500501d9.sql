SELECT
  c.h01 AS customer_id,
  c.h03 AS customer_first_name,
  c.h04 AS customer_last_name,
  COUNT(p.p01) AS payment_count,
  ROUND(SUM(p.p05), 2) AS total_amount,
  ROUND(AVG(p.p05), 2) AS average_payment_amount,
  ROUND(
    SUM(CASE WHEN s.o07 <> c.h02 THEN p.p05 ELSE 0 END) * 1.0 / SUM(p.p05),
    4
  ) AS other_store_staff_amount_share
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
JOIN stf AS s
  ON s.o01 = p.p03
WHERE p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04
HAVING COUNT(p.p01) > 5
   AND SUM(p.p05) > 30
ORDER BY
  total_amount DESC,
  payment_count DESC,
  customer_id;