WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month,
        SUM(p.p05) AS total_amount,
        COUNT(p.p01) AS payment_count,
        MAX(p.p03) AS top_staff_id,
        c.h02 AS store_id
    FROM pay p
    JOIN cus c ON p.p02 = c.h01
    WHERE strftime('%Y', p.p06) = '2005'
    GROUP BY p.p02, strftime('%Y-%m', p.p06), c.h02
),
history AS (
    SELECT
        *,
        AVG(total_amount) OVER (
            PARTITION BY customer_id 
            ORDER BY month 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS prev_avg
    FROM monthly_stats
),
filtered AS (
    SELECT * FROM history
    WHERE prev_avg IS NOT NULL 
      AND total_amount >= 2 * prev_avg 
      AND payment_count >= 3
),
ranked_suspicious AS (
    SELECT 
        *,
        PERCENT_RANK() OVER (PARTITION BY store_id ORDER BY total_amount DESC) as p_rank
    FROM filtered
),
final_data AS (
    SELECT 
        f.*,
        sto.j01 AS store_id,
        cty.d02 AS city,
        cnt.c02 AS country,
        stf.o02 || ' ' || stf.o03 AS staff_name
    FROM ranked_suspicious f
    JOIN sto ON f.store_id = sto.j01
    JOIN adr ON sto.j03 = adr.e01
    JOIN cty ON adr.e05 = cty.d01
    JOIN cnt ON cty.d03 = cnt.c01
    JOIN stf ON f.top_staff_id = stf.o01
    WHERE f.p_rank <= 0.1
)
SELECT 
    store_id, city, country, month, total_amount, payment_count,
    (total_amount - prev_avg) AS deviation,
    RANK() OVER (PARTITION BY month ORDER BY total_amount DESC) AS rank_in_month,
    staff_name
FROM final_data
ORDER BY month, total_amount DESC;