SELECT
    c.c01 AS customer_id,
    c.c02 AS customer_name,
    c.c04 AS customer_state,
    COUNT(*) AS outgoing_txn_count,
    SUM(ABS(t.t02)) AS outgoing_txn_amount,
    SUM(CASE WHEN t.t04 <> c.c04 THEN 1 ELSE 0 END) AS out_of_state_txn_count
FROM btm_cst AS c
JOIN btm_accd AS a
    ON a.a01 = c.c01
JOIN btm_trn AS t
    ON t.t01 = a.a02
WHERE a.a03 = 'SAVINGS'
  AND a.a05 = 'ACTIVE'
  AND t.t02 < 0
  AND t.t05 >= '2020-01-01'
  AND t.t05 < '2020-02-01'
GROUP BY
    c.c01,
    c.c02,
    c.c04
HAVING
    out_of_state_txn_count > 2
    OR outgoing_txn_amount > 10000;