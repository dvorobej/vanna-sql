SELECT
  c.h01 AS customer_id,
  c.h03 || ' ' || c.h04 AS customer_full_name,
  COUNT(p.p01) AS payment_count,
  COALESCE(SUM(p.p05), 0) AS total_amount,
  COALESCE(AVG(p.p05), 0) AS average_payment,
  COALESCE(MAX(p.p05), 0) AS max_payment,
  CASE
    WHEN COALESCE(SUM(p.p05), 0) > 100 OR COUNT(p.p01) > 10 THEN 1
    ELSE 0
  END AS high_risk
FROM cus AS c
LEFT JOIN pay AS p
  ON p.p02 = c.h01
  AND p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
LEFT JOIN stf AS s
  ON s.o01 = p.p03
WHERE c.h07 IN ('1', 'Y')
GROUP BY
  c.h01,
  c.h03,
  c.h04
ORDER BY
  high_risk DESC,
  total_amount DESC,
  customer_full_name;