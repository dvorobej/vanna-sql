SELECT
  t01 AS account_number,
  t02 AS transaction_amount,
  t04 AS transaction_state,
  t05 AS transaction_date
FROM btm_trn
WHERE t03 = 'ATM withdrawal'
ORDER BY t05 DESC
LIMIT 10;