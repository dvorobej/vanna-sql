SELECT COUNT(p2.p01)
    FROM pay AS p2
    WHERE p2.p02 = c.h01
      AND p2.p06 >= '2005-06-01'
      AND p2.p06 < '2005-07-01'
  ) AS staff_payment_share
FROM pay AS p
JOIN cus AS c
  ON c.h01 = p.p02
JOIN stf AS s
  ON s.o01 = p.p03
WHERE p.p06 >= '2005-06-01'
  AND p.p06 < '2005-07-01'
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  s.o01
HAVING SUM(p.p05) > 50
ORDER BY total_amount DESC, payment_count DESC;