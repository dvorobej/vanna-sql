WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS total_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT i.n03) AS store_count,
        SUM(CASE WHEN ci.d02 <> c_city.d02 OR co.c02 <> c_country.c02 THEN 1 ELSE 0 END) AS foreign_store_payment_count
    FROM pay p
    JOIN ren r ON p.p04 = r.q01
    JOIN inv i ON r.q03 = i.n01
    JOIN sto s ON i.n03 = s.j01
    JOIN adr s_adr ON s.j03 = s_adr.e01
    JOIN cty s_city ON s_adr.e05 = s_city.d01
    JOIN cnt s_country ON s_city.d03 = s_country.c01
    JOIN cus c ON p.p02 = c.h01
    JOIN adr c_adr ON c.h06 = c_adr.e01
    JOIN cty c_city ON c_adr.e05 = c_city.d01
    JOIN cnt c_country ON c_city.d03 = c_country.c01
    JOIN stf st ON p.p03 = st.o01
    JOIN adr ci ON st.o04 = ci.e01
    JOIN cty co ON ci.e05 = co.d01
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_history AS (
    SELECT
        *,
        AVG(total_amount) OVER (
            PARTITION BY customer_id
            ORDER BY payment_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount,
        RANK() OVER (
            PARTITION BY customer_id
            ORDER BY total_amount DESC
        ) AS month_rank
    FROM monthly_customer_stats
),
category_spending AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        cat.g03 AS category_name,
        SUM(p.p05) AS cat_amount
    FROM pay p
    JOIN ren r ON p.p04 = r.q01
    JOIN inv i ON r.q03 = i.n01
    JOIN flc fc ON i.n02 = fc.l01
    JOIN cat ON fc.l02 = cat.g01
    GROUP BY p.p02, strftime('%Y-%m', p.p06), cat.g01
),
top_categories AS (
    SELECT
        customer_id,
        payment_month,
        GROUP_CONCAT(category_name, ', ') AS top_cats
    FROM (
        SELECT customer_id, payment_month, category_name,
               RANK() OVER (PARTITION BY customer_id, payment_month ORDER BY cat_amount DESC) as rnk
        FROM category_spending
    )
    WHERE rnk <= 2
    GROUP BY customer_id, payment_month
)
SELECT
    ch.payment_month,
    ch.total_amount,
    ch.payment_count,
    ROUND(CAST(ch.foreign_store_payment_count AS REAL) / ch.payment_count, 4) AS foreign_store_share,
    ch.max_payment,
    ch.month_rank,
    tc.top_cats
FROM customer_history ch
JOIN top_categories tc ON ch.customer_id = tc.customer_id AND ch.payment_month = tc.payment_month
WHERE ch.prev_avg_amount IS NOT NULL
  AND ch.total_amount > ch.prev_avg_amount * 3
  AND ch.payment_count >= 5
  AND ch.store_count >= 2
ORDER BY ch.payment_month, ch.total_amount DESC;