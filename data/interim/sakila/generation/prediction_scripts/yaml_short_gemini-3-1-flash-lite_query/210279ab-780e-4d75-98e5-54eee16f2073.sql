SELECT
  p01,
  p02,
  p03,
  p04,
  p05,
  p06,
  p07
FROM pay
WHERE p05 > 9.00
ORDER BY p06 DESC
LIMIT 20;