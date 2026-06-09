SELECT SUM(p2.p05)
    FROM pay AS p2
    JOIN stf AS s2 ON p2.p03 = s2.o01
    WHERE p2.p02 = c.h01
      AND p2.p06 >= '2005-07-01' AND p2.p06 < '2005-08-01'
      AND s2.o07 <> c.h02
  ) AS amount_from_other_store_staff
FROM cus AS c
JOIN pay AS p ON p.p02 = c.h01
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04
HAVING SUM(p.p05) > 50
ORDER BY total_amount DESC;