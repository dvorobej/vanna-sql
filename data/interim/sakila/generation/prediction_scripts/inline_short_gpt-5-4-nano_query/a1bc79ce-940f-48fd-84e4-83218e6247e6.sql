SELECT
  c.h03 || ' ' || c.h04 AS full_name,
  COUNT(p.p01) AS payment_count,
  SUM(p.p05) AS total_amount,
  AVG(p.p05) AS avg_payment_amount,
  MAX(p.p05) AS max_payment_amount,
  CASE
    WHEN SUM(p.p05) > 100 OR COUNT(p.p01) > 10 THEN 'повышенный риск'
    ELSE 'обычный'
  END AS risk_flag
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
JOIN stf AS s
  ON s.o01 = p.p03
WHERE
  c.h07 IN ('1', 'Y')
  AND p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04
ORDER BY
  total_amount DESC,
  payment_count DESC,
  full_name;