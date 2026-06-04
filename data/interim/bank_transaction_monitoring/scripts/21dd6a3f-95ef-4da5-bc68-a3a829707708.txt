WITH RECURSIVE
months(month_no, month_key) AS (
    SELECT 1, '2020-01'
    UNION ALL
    SELECT month_no + 1, printf('2020-%02d', month_no + 1)
    FROM months
    WHERE month_no < 12
),
active_linked_accounts AS (
    SELECT DISTINCT
        c.c01 AS client_id,
        c.c02 AS client_name,
        c.c04 AS state_code,
        s.s02 AS account_no,
        s.s04 AS current_balance
    FROM btm_cst AS c
    JOIN btm_accs AS s
        ON s.s01 = c.c01
    JOIN btm_rel AS r
        ON r.r02 = s.s02
    WHERE upper(s.s05) = 'ACTIVE'
),
client_balances AS (
    SELECT
        client_id,
        client_name,
        state_code,
        SUM(current_balance) AS total_current_balance
    FROM active_linked_accounts
    GROUP BY client_id, client_name, state_code
),
state_balance_ranked AS (
    SELECT
        state_code,
        total_current_balance,
        ROW_NUMBER() OVER (
            PARTITION BY state_code
            ORDER BY total_current_balance
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY state_code
        ) AS cnt
    FROM client_balances
),
state_median_balances AS (
    SELECT
        state_code,
        AVG(total_current_balance) AS median_state_balance
    FROM state_balance_ranked
    WHERE rn IN ((cnt + 1) / 2, (cnt + 2) / 2)
    GROUP BY state_code
),
monthly_outgoing_actual AS (
    SELECT
        aa.client_id,
        substr(t.t05, 1, 7) AS month_key,
        SUM(-t.t02) AS outgoing_amount,
        group_concat(DISTINCT aa.account_no) AS affected_accounts
    FROM active_linked_accounts AS aa
    JOIN btm_trn AS t
        ON t.t01 = aa.account_no
    WHERE t.t02 < 0
      AND t.t05 >= '2020-01-01'
      AND t.t05 < '2021-01-01'
    GROUP BY aa.client_id, substr(t.t05, 1, 7)
),
client_monthly_outgoing AS (
    SELECT
        cb.client_id,
        cb.client_name,
        cb.state_code,
        m.month_key,
        COALESCE(moa.outgoing_amount, 0) AS outgoing_amount,
        moa.affected_accounts
    FROM client_balances AS cb
    CROSS JOIN months AS m
    LEFT JOIN monthly_outgoing_actual AS moa
        ON moa.client_id = cb.client_id
       AND moa.month_key = m.month_key
),
client_monthly_avg AS (
    SELECT
        client_id,
        AVG(outgoing_amount) AS avg_monthly_outgoing
    FROM client_monthly_outgoing
    GROUP BY client_id
),
notification_channel AS (
    SELECT
        m03 AS recommended_channel
    FROM btm_msg
    WHERE m01 = 'Balance Alert'
    ORDER BY m03
    LIMIT 1
)
SELECT
    cmo.client_id,
    cmo.client_name,
    cmo.state_code,
    cmo.month_key AS anomaly_month,
    cmo.outgoing_amount,
    cmo.outgoing_amount - cma.avg_monthly_outgoing AS deviation_from_average,
    cmo.affected_accounts,
    nc.recommended_channel
FROM client_monthly_outgoing AS cmo
JOIN client_monthly_avg AS cma
    ON cma.client_id = cmo.client_id
JOIN client_balances AS cb
    ON cb.client_id = cmo.client_id
JOIN state_median_balances AS smb
    ON smb.state_code = cb.state_code
CROSS JOIN notification_channel AS nc
WHERE cmo.outgoing_amount > 2 * cma.avg_monthly_outgoing
  AND cb.total_current_balance < smb.median_state_balance
ORDER BY
    cmo.state_code,
    cmo.client_id,
    cmo.month_key;