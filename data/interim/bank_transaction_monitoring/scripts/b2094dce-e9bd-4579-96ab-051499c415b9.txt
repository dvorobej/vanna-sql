SELECT
  t01,
  t02,
  t04,
  t05
FROM btm_trn
WHERE t03 = 'ATM withdrawal'
  AND t02 < 0
ORDER BY t05 DESC
LIMIT 10;