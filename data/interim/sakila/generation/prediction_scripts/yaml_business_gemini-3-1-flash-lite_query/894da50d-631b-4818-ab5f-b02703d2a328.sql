WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS total_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT i.n03) AS store_count,
        SUM(CASE WHEN i.n03 <> c.h02 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS foreign_store_share
    FROM pay p
    JOIN cus c ON c.h01 = p.p02
    JOIN ren r ON r.q01 = p.p04
    JOIN inv i ON i.n01 = r.q03
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ct ON ct.d01 = a.e05
    JOIN sto s ON s.j01 = i.n03
    JOIN adr sa ON sa.e01 = s.j03
    JOIN cty sct ON sct.d01 = sa.e05
    WHERE (ct.d02 <> sct.d02 OR ct.d03 <> sct.d03)
    GROUP BY p.p02, date(p.p06, 'start of month')
),
history AS (
    SELECT
        ms.*,
        AVG(ms.total_amount) OVER (
            PARTITION BY ms.customer_id
            ORDER BY ms.month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount,
        RANK() OVER (
            PARTITION BY ms.customer_id
            ORDER BY ms.total_amount DESC
        ) AS month_rank
    FROM monthly_stats ms
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
),
top_categories AS (
    SELECT
        cs.customer_id,
        cs.month_start,
        GROUP_CONCAT(cs.category_name, ', ') AS main_categories
    FROM category_spending cs
    WHERE cs.cat_amount = (
        SELECT MAX(cat_amount) 
        FROM category_spending cs2 
        WHERE cs2.customer_id = cs.customer_id AND cs2.month_start = cs.month_start
    )
    GROUP BY cs.customer_id, cs.month_start
)
SELECT
    h.month_start AS month,
    h.total_amount,
    h.payment_count,
    ROUND(h.foreign_store_share, 4) AS foreign_store_share,
    h.max_payment,
    h.month_rank,
    tc.main_categories
FROM history h
JOIN top_categories tc ON tc.customer_id = h.customer_id AND tc.month_start = h.month_start
WHERE h.prev_avg_amount IS NOT NULL
  AND h.total_amount > h.prev_avg_amount * 3
  AND h.payment_count >= 5
  AND h.store_count >= 2
ORDER BY h.month_start, h.total_amount DESC;