SELECT
  c.h01 AS customer_id,
  c.h03 AS customer_first_name,
  c.h04 AS customer_last_name,
  s2.j01 AS store_id,
  COUNT(p.p01) AS payment_count,
  ROUND(SUM(p.p05), 2) AS total_amount,
  ROUND(AVG(p.p05), 2) AS avg_payment_amount,
  MAX(p.p05) AS max_payment_amount,
  CASE
    WHEN COUNT(p.p01) > 10 THEN 1
    ELSE 0
  END AS more_than_10_payments_flag
FROM pay AS p
JOIN cus AS c
  ON c.h01 = p.p02
JOIN stf AS st
  ON st.o01 = p.p03
JOIN sto AS s2
  ON s2.j01 = st.o07
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  s2.j01
HAVING SUM(p.p05) > 50
ORDER BY total_amount DESC, payment_count DESC, customer_id, store_id;