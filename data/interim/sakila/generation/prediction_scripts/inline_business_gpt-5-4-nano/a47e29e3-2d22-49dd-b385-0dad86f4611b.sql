SELECT
  c.h01 AS customer_id,
  c.h03 || ' ' || c.h04 AS customer_name,
  s2.j01 AS customer_store_id,
  st.o01 AS staff_id,
  st.o02 || ' ' || st.o03 AS staff_name,
  COUNT(p.p01) AS payment_count,
  ROUND(SUM(p.p05), 2) AS total_amount,
  ROUND(AVG(p.p05), 2) AS avg_check,
  ROUND(MAX(p.p05), 2) AS max_check,
  SUM(CASE WHEN p.p05 > 8.00 THEN p.p05 ELSE 0 END) AS amount_over_8,
  ROUND(
    1.0 * SUM(CASE WHEN p.p05 > 8.00 THEN p.p05 ELSE 0 END) / SUM(p.p05),
    4
  ) AS share_amount_over_8
FROM cus AS c
JOIN sto AS s2
  ON s2.j01 = c.h02
JOIN pay AS p
  ON p.p02 = c.h01
JOIN stf AS st
  ON st.o01 = p.p03
WHERE p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  s2.j01,
  st.o01,
  st.o02,
  st.o03
HAVING SUM(p.p05) > 50
ORDER BY total_amount DESC, payment_count DESC, customer_id;