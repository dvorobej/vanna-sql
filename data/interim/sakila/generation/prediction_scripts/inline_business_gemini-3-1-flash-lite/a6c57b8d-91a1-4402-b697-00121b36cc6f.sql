WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS total_amount,
        MAX(p.p05) AS max_payment
    FROM pay p
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_history AS (
    SELECT
        mcs.*,
        AVG(mcs.total_amount) OVER (
            PARTITION BY mcs.customer_id
            ORDER BY mcs.payment_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS avg_prev_amount
    FROM monthly_customer_stats mcs
),
country_stats AS (
    SELECT
        mcs.payment_month,
        c.c01 AS country_id,
        c.c02 AS country_name,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY mcs.total_amount) OVER (
            PARTITION BY mcs.payment_month, c.c01
        ) AS p90_amount
    FROM monthly_customer_stats mcs
    JOIN cus cu ON cu.h01 = mcs.customer_id
    JOIN adr a ON a.e01 = cu.h06
    JOIN cty ci ON ci.d01 = a.e05
    JOIN cnt c ON c.c01 = ci.d03
),
top