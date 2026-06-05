SELECT
  c.h03 || ' ' || c.h04 AS customer_full_name,
  s.o02 || ' ' || s.o03 AS staff_full_name,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  CASE
    WHEN SUM(p.p05) > 50 THEN 1
    ELSE 0
  END AS high_attention_flag
FROM pay AS p
JOIN cus AS c ON c.h01 = p.p02
JOIN stf AS s ON s.o01 = p.p03
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  s.o01,
  s.o02,
  s.o03
HAVING COUNT(p.p01) >= 5
ORDER BY total_amount DESC, payment_count DESC;