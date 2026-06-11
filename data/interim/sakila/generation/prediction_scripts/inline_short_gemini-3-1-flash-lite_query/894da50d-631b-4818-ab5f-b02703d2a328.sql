WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT s.o07) AS store_count,
        SUM(CASE WHEN a_cus.e05 <> a_sto.e05 OR cnt_cus.c01 <> cnt_sto.c01 THEN 1 ELSE 0 END) AS foreign_store_payments
    FROM pay p
    JOIN cus c ON c.h01 = p.p02
    JOIN adr a_cus ON a_cus.e01 = c.h06
    JOIN cty ct_cus ON ct_cus.d01 = a_cus.e05
    JOIN cnt cnt_cus ON cnt_cus.c01 = ct_cus.d03
    JOIN stf s ON s.o01 = p.p03
    JOIN sto st ON st.j01 = s.o07
    JOIN adr a_sto ON a_sto.e01 = st.j03
    JOIN cty ct_sto ON ct_sto.d01 = a_sto.e05
    JOIN cnt cnt_sto ON cnt_sto.c01 = ct_sto.d03
    WHERE p.p04 IS NOT NULL
    GROUP BY p.p02, date(p.p06, 'start of month')
),
monthly_with_history AS (
    SELECT
        *,
        AVG(monthly_amount) OVER (
            PARTITION BY customer_id
            ORDER BY month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount,
        RANK() OVER (
            PARTITION BY customer_id
            ORDER BY monthly_amount DESC
        ) AS amount_rank
    FROM monthly_payments
),
category_spending AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        cat.g02 AS category_name,
        SUM(p.p05) AS cat_amount
    FROM pay p
    JOIN ren r ON r.q01 = p.p04
    JOIN inv i ON i.n01 = r.q03
    JOIN flc fc ON fc.l01 = i.n02
    JOIN cat ON cat.g01 = fc.l02
    GROUP BY p.p02, date(p.p06, 'start of month'), cat.g02
)
SELECT
    m.month_start,
    m.monthly_amount,
    m.payment_count,
    ROUND(CAST(m.foreign_store_payments AS REAL) / m.payment_count, 4) AS foreign_store_share,
    m.max_payment,
    m.amount_rank,
    GROUP_CONCAT(cs.category_name, ', ') AS top_categories
FROM monthly_with_history m
JOIN category_spending cs ON cs.customer_id = m.customer_id AND cs.month_start = m.month_start
WHERE m.prev_avg_amount IS NOT NULL
  AND m.monthly_amount > m.prev_avg_amount * 3
  AND m.payment_count >= 5
  AND m.store_count > 1
  AND m.foreign_store_payments > 0
  AND cs.cat_amount >= (SELECT MAX(cat_amount) FROM category_spending WHERE customer_id = m.customer_id AND month_start = m.month_start) * 0.5
GROUP BY m.customer_id, m.month_start
ORDER BY m.month_start, m.monthly_amount DESC;