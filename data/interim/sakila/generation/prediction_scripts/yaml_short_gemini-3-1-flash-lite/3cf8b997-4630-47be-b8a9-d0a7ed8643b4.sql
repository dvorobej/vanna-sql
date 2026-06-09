WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month,
        SUM(p.p05) AS total_amount,
        COUNT(p.p01) AS payment_count,
        c.h02 AS store_id,
        ci.d02 AS city,
        co.c02 AS country,
        MAX(p.p03) AS top_staff_id -- Simplified: staff with max ID for the month
    FROM pay p
    JOIN cus c ON p.p02 = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ci ON a.e05 = ci.d01
    JOIN cnt co ON ci.d03 = co.c01
    WHERE strftime('%Y', p.p06) = '2005'
    GROUP BY p.p02, strftime('%Y-%m', p.p06), c.h02, ci.d02, co.c02
),
history AS (
    SELECT *,
        AVG(total_amount) OVER (PARTITION BY customer_id ORDER BY month ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING) AS prev_avg
    FROM monthly_stats
),
filtered AS (
    SELECT *,
        (total_amount / NULLIF(prev_avg, 0)) AS ratio,
        PERCENT_RANK() OVER (PARTITION BY store_id, month ORDER BY total_amount DESC) AS p_rank
    FROM history
    WHERE prev_avg IS NOT NULL
      AND total_amount >= 2 * prev_avg
      AND payment_count >= 3
),
final_selection AS (
    SELECT * FROM filtered WHERE p_rank <= 0.1
)
SELECT
    s.j01 AS store_id,
    f.city,
    f.country,
    f.month,
    f.total_amount,
    f.payment_count,
    (f.total_amount - f.prev_avg) AS deviation,
    f.p_rank AS risk_rank,
    st.o02 || ' ' || st.o03 AS top_staff_name
FROM final_selection f
JOIN sto s ON f.store_id = s.j01
JOIN stf st ON f.top_staff_id = st.o01
ORDER BY f.month, f.total_amount DESC;