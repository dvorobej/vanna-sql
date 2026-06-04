SELECT
  t01 AS account_number,
  t02 AS amount,
  t03 AS channel,
  t04 AS state,
  t05 AS transaction_date
FROM btm_trn
WHERE t02 < 0
ORDER BY t05 DESC
LIMIT 10;