WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT i.n03) AS distinct_stores_count,
        SUM(CASE WHEN i.n03 <> c.h02 THEN 1 ELSE 0 END) AS foreign_store_payment_count,
        COUNT(*) AS total_payments_in_month
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    GROUP BY p.p02, date(p.p06, 'start of month')
),
monthly_with_history AS (
    SELECT
        mp.*,
        AVG(mp.monthly_amount) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount
    FROM monthly_payments AS mp
),
geo_mismatch AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    JOIN sto AS s ON s.j01 = i.n03
    JOIN adr AS sa ON sa.e01 = s.j02
    JOIN cty AS sct ON sct.d01 = sa.e05
    WHERE ct.d01 <> sct.d01 OR ct.d03 <> sct.d03
    GROUP BY p.p02, date(p.p06, 'start of month')
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
        cs.customer_id,
        cs.month_start,
        GROUP_CONCAT(cs.category_name, ', ') AS top_cats
    FROM category_spending cs
    WHERE cs.cat_amount = (
        SELECT MAX(cat_amount) 
        FROM category_spending 
        WHERE customer_id = cs.customer_id AND month_start = cs.month_start
    )
    GROUP BY cs.customer_id, cs.month_start
)
SELECT
    strftime('%Y-%m', mwh.month_start) AS month,
    mwh.monthly_amount,
    mwh.payment_count,
    ROUND(CAST(mwh.foreign_store_payment_count AS REAL) / mwh.total_payments_in_month, 4) AS foreign_store_share,
    mwh.max_payment,
    RANK() OVER (PARTITION BY mwh.customer_id ORDER BY mwh.monthly_amount DESC) AS customer_month_rank,
    tc.top_cats
FROM monthly_with_history mwh
JOIN geo_mismatch gm ON gm.customer_id = mwh.customer_id AND gm.month_start = mwh.month_start
JOIN top_categories tc ON tc.customer_id = mwh.customer_id AND tc.month_start = mwh.month_start
WHERE mwh.prev_avg_amount IS NOT NULL
  AND mwh.monthly_amount > 3 * mwh.prev_avg_amount
  AND mwh.payment_count >= 5
  AND mwh.distinct_stores_count > 1;