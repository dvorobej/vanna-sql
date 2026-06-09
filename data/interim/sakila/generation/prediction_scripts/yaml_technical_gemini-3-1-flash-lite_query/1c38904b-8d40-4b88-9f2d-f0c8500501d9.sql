SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  COUNT(p.p01) AS payment_count,
  ROUND(SUM(p.p05), 2) AS total_amount,
  ROUND(AVG(p.p05), 2) AS average_payment,
  ROUND(
    SUM(CASE WHEN s.o07 <> c.h02 THEN 1 ELSE 0 END) * 1.0 / COUNT(p.p01),
    4
  ) AS other_store_staff_share
FROM pay AS p
JOIN cus AS c
  ON p.p02 = c.h01
JOIN stf AS s
  ON p.p03 = s.o01
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
  payment_count DESC;