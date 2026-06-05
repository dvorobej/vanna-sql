SELECT
  c.h03 AS first_name,
  c.h04 AS last_name,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  AVG(p.p05) AS avg_payment,
  SUM(CASE WHEN p.p05 > 8.00 THEN 1 ELSE 0 END) AS large_payment_count
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
WHERE c.h07 IN ('1', 'Y')
  AND p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY c.h01, c.h03, c.h04
HAVING COUNT(p.p01) >= 10
ORDER BY payment_count DESC, total_amount DESC;