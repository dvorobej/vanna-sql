SELECT
  c.h03 || ' ' || c.h04 AS full_name,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  AVG(p.p05) AS average_payment,
  MAX(p.p05) AS max_payment,
  CASE
    WHEN SUM(p.p05) > 100 OR COUNT(p.p01) > 10 THEN 1
    ELSE 0
  END AS high_risk_flag
FROM cus AS c
JOIN pay AS p
  ON c.h01 = p.p02
JOIN stf AS s
  ON p.p03 = s.o01
WHERE c.h07 IN ('1', 'Y')
  AND p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04
ORDER BY
  total_amount DESC,
  payment_count DESC;