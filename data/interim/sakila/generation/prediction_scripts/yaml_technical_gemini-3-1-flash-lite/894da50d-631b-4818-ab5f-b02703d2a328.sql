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
        cs.customer_id,
        cs.payment_month,
        GROUP_CONCAT(cs.category_name, ', ') AS categories
    FROM category_spending cs
    JOIN (
        SELECT customer_id, payment_month, MAX(cat_amount) as max_cat
        FROM category_spending
        GROUP BY customer_id, payment_month
    ) top ON cs.customer_id = top.customer_id 
         AND cs.payment_month = top.payment_month 
         AND cs.cat_amount = top.max_cat
    GROUP BY cs.customer_id, cs.payment_month
)
SELECT
    fm.payment_month,
    fm.customer_id,
    fm.monthly_amount,
    fm.payment_count,
    fm.off_store_share,
    fm.max_payment,
    RANK() OVER (PARTITION BY fm.customer_id ORDER BY fm.monthly_amount DESC) AS month_rank,
    tc.categories
FROM filtered_months fm
JOIN top_categories tc ON fm.customer_id = tc.customer_id AND fm.payment_month = tc.payment_month
JOIN cus c ON fm.customer_id = c.h01
JOIN adr a ON c.h06 = a.e01
JOIN cty ci ON a.e05 = ci.d01
JOIN inv i ON 1=1 -- Logic for cross-store check
JOIN sto st ON i.n03 = st.j01
JOIN adr sa ON st.j03 = sa.e01
WHERE ci.d03 <> sa.e05 -- City/Country mismatch check
ORDER BY fm.payment_month, fm.monthly_amount DESC;