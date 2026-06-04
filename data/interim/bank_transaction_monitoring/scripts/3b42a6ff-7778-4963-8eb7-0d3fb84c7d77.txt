SELECT
    c.c01 AS client_id,
    c.c02 AS client_name,
    SUM(ABS(t.t02)) AS total_outgoing_amount,
    COUNT(*) AS total_outgoing_count,
    SUM(CASE WHEN t.t04 <> c.c04 THEN ABS(t.t02) ELSE 0 END) AS out_of_state_outgoing_amount,
    SUM(CASE WHEN t.t04 <> c.c04 THEN 1 ELSE 0 END) AS out_of_state_outgoing_count
FROM btm_cst AS c
JOIN btm_accd AS a
    ON a.a01 = c.c01
JOIN btm_trn AS t
    ON t.t01 = a.a02
WHERE a.a03 = 'SAVINGS'
  AND a.a05 = 'ACTIVE'
  AND t.t02 < 0
  AND t.t05 >= '2020-01-01'
  AND t.t05 < '2021-01-01'
GROUP BY
    c.c01,
    c.c02
HAVING SUM(CASE WHEN t.t04 <> c.c04 THEN ABS(t.t02) ELSE 0 END) > 10000;