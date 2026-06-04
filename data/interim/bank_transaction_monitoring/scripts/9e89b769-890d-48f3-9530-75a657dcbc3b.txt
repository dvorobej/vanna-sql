SELECT
    c.c01 AS customer_id,
    c.c02 AS customer_name,
    a.a03 AS account_type,
    COUNT(*) AS transaction_count,
    SUM(ABS(t.t02)) AS total_transaction_volume,
    SUM(CASE WHEN t.t02 < 0 THEN ABS(t.t02) ELSE 0 END) AS debit_amount,
    SUM(CASE WHEN t.t02 > 0 THEN t.t02 ELSE 0 END) AS credit_amount
FROM btm_cst AS c
JOIN btm_accd AS a
    ON a.a01 = c.c01
JOIN btm_trn AS t
    ON t.t01 = a.a02
WHERE a.a05 = 'ACTIVE'
  AND t.t05 >= '2020-01-01'
  AND t.t05 < '2020-02-01'
GROUP BY
    c.c01,
    c.c02,
    a.a03
HAVING SUM(CASE WHEN t.t02 < 0 THEN ABS(t.t02) ELSE 0 END) > 10000
ORDER BY
    c.c01,
    a.a03;