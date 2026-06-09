WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS monthly_amount,
        MAX(p.p05) AS max_payment
    FROM pay p
    WHERE p.p06 BETWEEN '2005-01-01' AND '2005-12-31 23:59:59'
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_history AS (
    SELECT
        mcs.*,
        AVG(mcs.monthly_amount) OVER (
            PARTITION BY mcs.customer_id 
            ORDER BY mcs.payment_month 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS avg_prev_amount
    FROM monthly_customer_stats mcs
),
country_stats AS (
    SELECT
        c.h01 AS customer_id,
        co.c01 AS country_id,
        co.c02 AS country_name,
        ci.d02 AS city_name,
        PERCENT_RANK() OVER (
            PARTITION BY co.c01, mcs.payment_month 
            ORDER BY mcs.monthly_amount DESC
        ) AS country_percentile
    FROM monthly_customer_stats mcs
    JOIN cus c ON c.h01 = mcs.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ci ON ci.d01 = a.e05
    JOIN cnt co ON co.c01 = ci.d03
),
top_staff AS (
    SELECT customer_id, payment_month, staff_id
    FROM (
        SELECT 
            p.p02 AS customer_id, 
            strftime('%Y-%m', p.p06) AS payment_month, 
            p.p03 AS staff_id,
            SUM(p.p05) AS staff_sum,
            ROW_NUMBER() OVER (PARTITION BY p.p02, strftime('%Y-%m', p.p06) ORDER BY SUM(p.p05) DESC) as rn
        FROM pay p
        GROUP BY p.p02, strftime('%Y-%m', p.p06), p.p03
    ) WHERE rn = 1
)
SELECT
    ch.payment_month,
    ch.customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    cs.country_name,
    cs.city_name,
    ch.monthly_amount,
    ch.payment_count,
    ROUND(ch.monthly_amount / NULLIF(ch.avg_prev_amount, 0), 2) AS ratio_vs_personal_avg,
    cs.country_percentile,
    ts.staff_id AS top_staff_id,
    s.o02 || ' ' || s.o03 AS top_staff_name
FROM customer_history ch
JOIN country_stats cs ON cs.customer_id = ch.customer_id
JOIN cus c ON c.h01 = ch.customer_id
JOIN top_staff ts ON ts.customer_id = ch.customer_id AND ts.payment_month = ch.payment_month
JOIN stf s ON s.o01 = ts.staff_id
WHERE ch.avg_prev_amount IS NOT NULL
  AND ch.monthly_amount > (ch.avg_prev_amount * 2)
  AND cs.country_percentile <= 0.10
ORDER BY ch.payment_month, cs.country_name, ch.monthly_amount DESC;