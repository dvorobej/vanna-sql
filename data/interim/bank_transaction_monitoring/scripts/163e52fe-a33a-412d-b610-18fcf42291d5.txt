SELECT
  t01,
  t02,
  t05
FROM btm_trn
WHERE t03 = 'ATM withdrawal'
  AND t04 = 'NY'
ORDER BY t05 DESC
LIMIT 10;