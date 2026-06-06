WITH main_savings AS (
    SELECT
        c.c01 AS client_id,
        c.c02 AS client_name,
        c.c04 AS client_state,
        s.s02 AS main_account,
        s.s04 AS main_balance
    FROM btm_cst AS c
    JOIN btm_accs AS s
        ON s.s01 = c.c01
    WHERE s.s03 = 'SAVINGS'
      AND s.s05 = 'ACTIVE'
      AND s.s04 > 0
),
account_scope AS (
    SELECT
        client_id,
        client_name,
        client_state,
        main_account,
        main_balance,
        main_account AS account_no
    FROM main_savings

    UNION

    SELECT
        m.client_id,
        m.client_name,
        m.client_state,
        m.main_account,
        m.main_balance,
        a.s02 AS account_no
    FROM main_savings AS m
    JOIN btm_rel AS r
        ON r.r04 = m.main_account
    JOIN btm_accs AS a
        ON a.s01 = m.client_id
       AND a.s02 = r.r02
    WHERE a.s05 = 'ACTIVE'

    UNION

    SELECT
        m.client_id,
        m.client_name,
        m.client_state,
        m.main_account,
        m.main_balance,
        a.s02 AS account_no
    FROM main_savings AS m
    JOIN btm_rel AS r
        ON r.r04 = m.main_account
    JOIN btm_accs AS a
        ON a.s01 = m.client_id
       AND a.s02 = r.r02
    WHERE UPPER(REPLACE(COALESCE(a.s03, r.r03), ' ', '')) = 'CREDITCARD'
),
outgoing_txn AS (
    SELECT
        a.client_id,
        a.client_name,
        a.client_state,
        a.main_account,
        a.main_balance,
        t.t01 AS account_no,
        -t.t02 AS outgoing_amount,
        t.t04 AS txn_state,
        strftime('%m', t.t05) AS txn_month
    FROM account_scope AS a
    JOIN btm_trn AS t
        ON t.t01 = a.account_no
    WHERE t.t02 < 0
      AND t.t05 >= '2020-01-01'
      AND t.t05 < '2021-01-01'
),
monthly_agg AS (
    SELECT
        client_id,
        client_name,
        main_account,
        txn_month,
        SUM(outgoing_amount) AS outgoing_sum,
        COUNT(*) AS outgoing_count,
        SUM(CASE WHEN txn_state IS NOT NULL AND txn_state <> client_state THEN 1 ELSE 0 END) AS out_of_state_count,
        main_balance,
        CAST(SUM(outgoing_amount) AS REAL) / main_balance AS balance_share,
        client_state
    FROM outgoing_txn
    GROUP BY
        client_id,
        client_name,
        main_account,
        txn_month,
        main_balance,
        client_state
),
monthly_with_avg AS (
    SELECT
        monthly_agg.*,
        AVG(balance_share) OVER (PARTITION BY txn_month) AS avg_month_share
    FROM monthly_agg
),
state_rank AS (
    SELECT
        client_id,
        main_account,
        txn_month,
        txn_state,
        COUNT(*) AS txn_state_count,
        ROW_NUMBER() OVER (
            PARTITION BY client_id, main_account, txn_month
            ORDER BY COUNT(*) DESC, txn_state
        ) AS rn
    FROM outgoing_txn
    GROUP BY
        client_id,
        main_account,
        txn_month,
        txn_state
)
SELECT
    m.client_id,
    m.client_name,
    m.main_account,
    m.txn_month AS month_2020,
    ROUND(m.outgoing_sum, 2) AS outgoing_sum,
    m.outgoing_count,
    ROUND(m.balance_share, 6) AS balance_share,
    m.client_state,
    sr.txn_state AS most_frequent_txn_state
FROM monthly_with_avg AS m
JOIN state_rank AS sr
    ON sr.client_id = m.client_id
   AND sr.main_account = m.main_account
   AND sr.txn_month = m.txn_month
   AND sr.rn = 1
WHERE m.outgoing_sum > 0.10 * m.main_balance
  AND m.out_of_state_count > 0
  AND m.balance_share > m.avg_month_share
ORDER BY
    m.client_id,
    m.main_account,
    m.txn_month;