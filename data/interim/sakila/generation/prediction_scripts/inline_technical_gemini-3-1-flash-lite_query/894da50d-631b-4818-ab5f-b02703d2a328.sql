WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT i.n03) AS store_count,
        MAX(p.p05) AS max_payment,
        SUM(CASE WHEN c.h06 != a.e01 OR ct.d01 != cty.d01 THEN 1 ELSE 0 END) AS foreign_store_payments
    FROM pay p
    JOIN ren r ON p.p04 = r.q01
    JOIN inv i ON r.q03 = i.n01
    JOIN cus c ON p.p02 = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ct ON a.e05 = ct.d01
    JOIN sto s ON i.n03 = s.j01
    JOIN adr sa ON s.j03 = sa.e01
    JOIN cty cty ON sa.e05 = cty.d01
    GROUP BY p.p02, date(p.p06, 'start of month')
    HAVING COUNT(DISTINCT i.n03) > 1
       AND payment_count >= 5
),
history AS (
    SELECT
        *,
        AVG(monthly_amount) OVER (
            PARTITION BY customer_id
            ORDER BY month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg
    FROM monthly_payments
),
top_categories AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        cat.g02 AS category_name,
        SUM(p.p05) AS cat_sum,
        RANK() OVER (PARTITION BY p.p02, date(p.p06, 'start of month') ORDER BY SUM(p.p05) DESC) as cat_rank
    FROM pay p
    JOIN ren r ON p.p04 = r.q01
    JOIN inv i ON r.q03 = i.n01
    JOIN flc f ON i.n02 = f.l01
    JOIN cat ON f.l02 = cat.g01
    GROUP BY p.p02, date(p.p06, 'start of month'), cat.g02
)
SELECT
    h.month_start,
    h.monthly_amount,
    h.payment_count,
    ROUND(CAST(h.foreign_store_payments AS REAL) / h.payment_count, 2) AS foreign_store_share,
    h.max_payment,
    RANK() OVER (PARTITION BY h.customer_id ORDER BY h.monthly_amount DESC) AS month_rank,
    GROUP_CONCAT(tc.category_name, ', ') AS top_categories
FROM history h
JOIN top_categories tc ON h.customer_id = tc.customer_id AND h.month_start = tc.month_start
WHERE h.prev_avg > 0
  AND h.monthly_amount > 3 * h.prev_avg
  AND tc.cat_rank = 1
GROUP BY h.customer_id, h.month_start;