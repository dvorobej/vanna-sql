WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS total_amount,
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
            PARTITION BY c.c01, mcs.payment_month
        ) AS p90_amount
    FROM monthly_customer_stats mcs
    JOIN cus cu ON cu.h01 = mcs.customer_id
    JOIN adr a ON a.e01 = cu.h06
    JOIN cty ci ON ci.d01 = a.e05
    JOIN cnt c ON c.c01 = ci.d03
),
top_staff AS (
    SELECT * FROM (
        SELECT
            p.p02 AS customer_id,
            strftime('%Y-%m', p.p06) AS payment_month,
            p.p03 AS staff_id,
            SUM(p.p05) AS staff_total,
            ROW_NUMBER() OVER (PARTITION BY p.p02, strftime('%Y-%m', p.p06) ORDER BY SUM(p.p05) DESC) as rn
        FROM pay p
        GROUP BY p.p02, strftime('%Y-%m', p.p06), p.p03
    ) WHERE rn = 1
)
SELECT
    ch.payment_month,
    ch.customer_id,
    cu.h03 || ' ' || cu.h04 AS customer_name,
    cnt.c02 AS country,
    ct.d02 AS city,
    ch.total_amount,
    ch.payment_count,
    ROUND(ch.total_amount / NULLIF(ch.avg_prev_amount, 0), 2) AS ratio_vs_personal_avg,
    RANK() OVER (PARTITION BY cnt.c01, ch.payment_month ORDER BY ch.total_amount DESC) AS country_rank,
    st.o02 || ' ' || st.o03 AS top_staff_name
FROM customer_history ch
JOIN cus cu ON cu.h01 = ch.customer_id
JOIN adr a ON a.e01 = cu.h06
JOIN cty ct ON ct.d01 = a.e05
JOIN cnt cnt ON cnt.c01 = ct.d03
JOIN country_stats cs ON cs.country_id = cnt.c01 AND cs.payment_month = ch.payment_month
JOIN top_staff ts ON ts.customer_id = ch.customer_id AND ts.payment_month = ch.payment_month
JOIN stf st ON st.o01 = ts.staff_id
WHERE ch.avg_prev_amount IS NOT NULL
  AND ch.total_amount > ch.avg_prev_amount * 2
  AND ch.total_amount >= cs.p90_amount
ORDER BY ch.payment_month, country_rank;