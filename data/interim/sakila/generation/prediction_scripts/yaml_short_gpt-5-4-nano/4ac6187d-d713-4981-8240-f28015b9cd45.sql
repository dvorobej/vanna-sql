SELECT
  c.h01 AS customer_id,
  c.h03 || ' ' || c.h04 AS customer_name,
  COUNT(p.p01) AS payment_count,
  ROUND(SUM(p.p05), 2) AS total_amount,
  ROUND(AVG(p.p05), 2) AS avg_payment_amount,
  ROUND(COALESCE(SUM(p2.p05), 0), 2) AS other_store_staff_amount
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
JOIN stf AS s
  ON s.o01 = p.p03
JOIN sto AS st
  ON st.j01 = s.o07
LEFT JOIN pay AS p2
  ON p2.p02 = c.h01
  AND p2.p06 >= '2005-07-01'
  AND p2.p06 < '2005-08-01'
  AND p2.p03 IS NOT NULL
LEFT JOIN stf AS s2
  ON s2.o01 = p2.p03
LEFT JOIN sto AS st2
  ON st2.j01 = s2.o07
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
  AND st2.j01 IS NOT NULL
GROUP BY
  c.h01,
  c.h03,
  c.h04
HAVING SUM(p.p05) > 50
ORDER BY total_amount DESC;