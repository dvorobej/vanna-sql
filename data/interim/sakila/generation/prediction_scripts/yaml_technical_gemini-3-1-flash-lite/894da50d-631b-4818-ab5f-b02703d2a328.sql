WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(p.p01) AS payment_count,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS staff_count,
        SUM(CASE WHEN s.o07 <> c.h02 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS off_store_share
    FROM pay p
    JOIN cus c ON c.h01 = p.p02
    JOIN stf s ON s.o01 = p.p03
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
history_stats AS (
    SELECT
        ms.*,
        AVG(ms.monthly_amount) OVER (
            PARTITION BY ms.customer_id 
            ORDER BY ms.payment_month 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount
    FROM monthly_stats ms
),
filtered_months AS (
    SELECT *
    FROM history_stats
    WHERE prev_avg_amount IS NOT NULL
      AND monthly_amount > 3 * prev_avg_amount
      AND payment_count >= 5
),
category_spending AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        cat.g02 AS category_name,
        SUM(p.p05) AS cat_amount
    FROM pay p
    JOIN ren r ON p.p04 = r.q01
    JOIN inv i ON r.q03 = i.n01
    JOIN flc fc ON i.n02 = fc.l01
    JOIN cat ON fc.l02 = cat.g01
    GROUP BY p.p02, strftime('%Y-%m', p.p06), cat.g02
),
top_categories AS (
    SELECT
        customer_id,
        payment_month,
        GROUP_CONCAT(category_name, ', ') AS categories
    FROM (
        SELECT customer_id, payment_month, category_name,
               RANK() OVER (PARTITION BY customer_id, payment_month ORDER BY cat_amount DESC) as rnk
        FROM category_spending
    ) WHERE rnk <= 3
    GROUP BY customer_id, payment_month
)
SELECT
    fm.payment_month,
    fm.customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    fm.monthly_amount,
    fm.payment_count,
    fm.off_store_share,
    fm.max_payment,
    RANK() OVER (PARTITION BY fm.customer_id ORDER BY fm.monthly_amount DESC) AS month_rank,
    tc.categories
FROM filtered_months fm
JOIN cus c ON fm.customer_id = c.h01
JOIN top_categories tc ON fm.customer_id = tc.customer_id AND fm.payment_month = tc.payment_month
WHERE EXISTS (
    SELECT 1 FROM pay p
    JOIN ren r ON p.p04 = r.q01
    JOIN inv i ON r.q03 = i.n01
    JOIN sto st ON i.n03 = st.j01
    JOIN adr a_sto ON st.j03 = a_sto.e01
    JOIN adr a_cus ON c.h06 = a_cus.e01
    WHERE p.p02 = fm.customer_id 
      AND strftime('%Y-%m', p.p06) = fm.payment_month
      AND a_sto.e05 <> a_cus.e05
)
ORDER BY fm.payment_month, fm.monthly_amount DESC;