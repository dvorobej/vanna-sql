SELECT SUM(p2.p05)
    FROM pay AS p2
    JOIN ren AS r2 ON r2.q01 = p2.p04
    WHERE p2.p02 = c.h01
      AND p2.p06 >= '2005-07-01'
      AND p2.p06 < '2005-08-01'
      AND r2.q04 IN (SELECT r.q04 FROM ren r WHERE r.q01 = p.p04)
  ) AS staff_total_amount_other_shop
FROM cus AS c
JOIN pay AS p
  ON p.p02 = c.h01
JOIN ren AS r
  ON r.q01 = p.p04
WHERE p.p06 >= '2005-07-01'
  AND p.p06 < '2005-08-01'
GROUP BY
  c.h01
HAVING SUM(p.p05) > 50
ORDER BY
  total_amount DESC,
  customer_id;