SELECT p02
    FROM pay
    WHERE p06 >= '2005-06-01' AND p06 < '2005-07-01'
    GROUP BY p02
    HAVING COUNT(p01) >= 5
  )
GROUP BY
  c.h01,
  c.h03,
  c.h04,
  s.o01,
  s.o02,
  s.o03
ORDER BY
  c.h01,
  total_amount DESC;