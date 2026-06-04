SELECT
  t01 AS account_number,
  ABS(t02) AS withdrawal_amount,
  t04 AS transaction_state,
  t05 AS transaction_date
FROM btm_trn
WHERE t03 = 'ATM withdrawal'
  AND t02 < 0
ORDER BY ABS(t02) DESC
LIMIT 10;