SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  COUNT(p.p01) AS payment_count,
  COALESCE(SUM(p.p05), 0) AS total_amount,
  COALESCE(AVG(p.p05), 0) AS average_amount,
  SUM(CASE WHEN s.o07 <> c.h02 THEN 1 ELSE 0 END) AS cross_store_operations,
  CASE
    WHEN COALESCE(SUM(p.p05), 0) > 50
      OR SUM(CASE WHEN s.o07 <> c.h02 THEN 1 ELSE 0 END) > 3
    THEN 1
    ELSE 0
  END AS needs_review
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
  c.h04,
  c.h02
ORDER BY
  needs_review DESC,
  total_amount DESC,
  c.h01;