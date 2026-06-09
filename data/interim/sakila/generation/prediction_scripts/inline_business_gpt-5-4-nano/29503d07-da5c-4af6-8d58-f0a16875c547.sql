SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  AVG(p.p05) AS average_payment_amount,
  SUM(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) AS large_payment_count_over_8
FROM cus AS c
JOIN ren AS r
  ON r.q04 = c.h01
JOIN pay AS p
  ON p.p04 = r.q01
WHERE c.h07 IN ('1', 'Y')
  AND p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04
HAVING
  SUM(p.p05) > 50.00
  OR SUM(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) >= 3
ORDER BY
  total_amount DESC,
  payment_count DESC,
  c.h01;