SELECT
    c.c01 AS client_id,
    c.c02 AS client_name,
    COUNT(*) AS expense_txn_count,
    SUM(-t.t02) AS total_expense_amount,
    SUM(CASE WHEN t.t03 LIKE 'ATM%' THEN -t.t02 ELSE 0 END) AS atm_withdrawal_amount
FROM btm_cst AS c
JOIN btm_accd AS a
    ON a.a01 = c.c01
JOIN btm_trn AS t
    ON t.t01 = a.a02
WHERE c.c04 = 'CA'
  AND a.a05 = 'ACTIVE'
  AND t.t05 >= '2020-01-01'
  AND t.t05 < '2020-02-01'
  AND t.t02 < 0
GROUP BY
    c.c01,
    c.c02
HAVING SUM(-t.t02) > 10000;