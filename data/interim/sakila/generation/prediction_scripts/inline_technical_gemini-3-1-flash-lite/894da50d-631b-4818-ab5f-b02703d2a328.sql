WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS payment_count,
        MAX(p.p05) AS max_payment
    FROM pay p
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_history AS (
    SELECT
        ms.*,
        AVG(ms.monthly_sum) OVER (
            PARTITION BY ms.customer_id 
            ORDER BY ms.payment_month 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_sum
    FROM monthly_stats ms
),
payment_details AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        p.p01 AS payment_id,
        CASE WHEN s.o07 <> c.h02 THEN 1 ELSE 0 END AS is_foreign_store,
        CASE WHEN ci_c.d01 <> ci_s.d01 THEN 1 ELSE 0 END AS is_foreign_city,
        cat.g02 AS category_name
    FROM pay p
    JOIN cus c ON p.p02 = c.h01
    JOIN stf s ON p.p03 = s.o01
    JOIN ren r ON p.p04 = r.q01
    JOIN inv i ON r.q03 = i.n01
    JOIN flc flc ON i.n02 = flc.l01
    JOIN cat ON flc.l02 = cat.g01
    JOIN adr a_c ON c.h06 = a_c.e01
    JOIN cty ci_c ON a_c.e05 = ci_c.d01
    JOIN adr a_s ON s.o07 = a_s.e01 -- Assuming store address link
    JOIN cty ci_s ON a_s.e05 = ci_s.d01
),
monthly_details AS (
    SELECT
        customer_id,
        payment_month,
        SUM(is_foreign_store) * 1.0 / COUNT(*) AS foreign_store_share,
        GROUP_CONCAT(DISTINCT category_name) AS categories
    FROM payment_details
    GROUP BY customer_id, payment_month
)
SELECT
    ch.payment_month,
    ch.customer_id,
    ch.monthly_sum,
    ch.payment_count,
    md.foreign_store_share,
    ch.max_payment,
    RANK() OVER (PARTITION BY ch.customer_id ORDER BY ch.monthly_sum DESC) AS month_rank,
    md.categories
FROM customer_history ch
JOIN monthly_details md ON ch.customer_id = md.customer_id AND ch.payment_month = md.payment_month
WHERE ch.monthly_sum > (ch.prev_avg_sum * 3)
  AND ch.payment_count >= 5
ORDER BY ch.customer_id, ch.payment_month;