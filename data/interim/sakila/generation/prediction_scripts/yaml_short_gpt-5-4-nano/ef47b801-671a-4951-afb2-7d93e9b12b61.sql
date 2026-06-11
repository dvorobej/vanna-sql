SELECT
  c.h01 AS customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  st.j01 AS store_id,
  COUNT(p.p01) AS payment_count,
  ROUND(AVG(p.p05), 2) AS avg_payment,
  ROUND(MAX(p.p05), 2) AS max_payment,
  CASE
    WHEN COUNT(p.p01) > 10 THEN 1
    ELSE 0
  END AS more_than_10_payments_flag
FROM pay AS p
JOIN cus AS c
  ON c.h01 = p.p02
JOIN sto AS st
  ON st.j01 = c.h02
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  st.j01
HAVING SUM(p.p05) > 50
ORDER BY total_amount DESC, payment_count DESC, customer_id, store_id;