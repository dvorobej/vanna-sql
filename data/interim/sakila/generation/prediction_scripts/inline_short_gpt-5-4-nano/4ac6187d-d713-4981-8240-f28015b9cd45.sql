SELECT ROUND(SUM(p2.p05), 2)
    FROM pay AS p2
    JOIN stf AS s2 ON s2.o01 = p2.p03
    WHERE p2.p02 = c.h01
      AND p2.p06 >= '2005-07-01'
      AND p2.p06 < '2005-08-01'
      AND s2.o07 <> s.o07
  ) AS other_store_staff_amount
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
JOIN stf AS s
  ON s.o01 = p.p03
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  s.o07
HAVING SUM(p.p05) > 50
ORDER BY
  total_amount DESC,
  customer_id;