WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT i.n03) AS distinct_store_count,
        SUM(CASE WHEN c.h06 <> a.e01 THEN 1 ELSE 0 END) AS foreign_store_payment_count
    FROM pay AS p
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    JOIN cus AS c ON c.h01 = p.p02
    JOIN adr AS a ON a.e01 = c.h06
    WHERE p.p04 IS NOT NULL
    GROUP BY p.p02, date(p.p06, 'start of month')
),
monthly_with_avg AS (
    SELECT
        mp.*,
        AVG(mp.monthly_amount) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount
    FROM monthly_payments AS mp
),
suspicious_months AS (
    SELECT *
    FROM monthly_with_avg
    WHERE prev_avg_amount IS NOT NULL
      AND monthly_amount > 3.0 * prev_avg_amount
      AND payment_count >= 5
      AND distinct_store_count > 1
),
category_spending AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        cat.g02 AS category_name,
        SUM(p.p05) AS cat_amount
    FROM pay AS p
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    JOIN flc AS fc ON fc.l01 = i.n02
    JOIN cat ON cat.g01 = fc.l02
    GROUP BY p.p02, date(p.p06, 'start of month'), cat.g02
),
top_categories AS (
    SELECT
        customer_id,
        month_start,
        GROUP_CONCAT(category_name, ', ') AS main_categories
    FROM (
        SELECT customer_id, month_start, category_name,
               RANK() OVER (PARTITION BY customer_id, month_start ORDER BY cat_amount DESC) as rnk
        FROM category_spending
    )
    WHERE rnk <= 2
    GROUP BY customer_id, month_start
)
SELECT
    strftime('%Y-%m', sm.month_start) AS month,
    sm.monthly_amount,
    sm.payment_count,
    ROUND(CAST(sm.foreign_store_payment_count AS REAL) / sm.payment_count, 4) AS foreign_store_share,
    sm.max_payment,
    RANK() OVER (PARTITION BY sm.customer_id ORDER BY sm.monthly_amount DESC) AS customer_month_rank,
    tc.main_categories
FROM suspicious_months AS sm
JOIN top_categories AS tc ON tc.customer_id = sm.customer_id AND tc.month_start = sm.month_start
ORDER BY sm.month_start, sm.monthly_amount DESC;