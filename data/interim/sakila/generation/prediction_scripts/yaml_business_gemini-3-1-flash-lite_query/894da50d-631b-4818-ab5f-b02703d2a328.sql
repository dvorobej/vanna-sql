WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT i.n03) AS store_count,
        SUM(CASE WHEN i.n03 <> c.h02 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS off_store_share
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN sto AS s ON s.j01 = i.n03
    JOIN adr AS sa ON sa.e01 = s.j03
    JOIN cty AS sct ON sct.d01 = sa.e05
    WHERE (ct.d02 <> sct.d02 OR ct.d03 <> sct.d03)
    GROUP BY p.p02, date(p.p06, 'start of month')
),
monthly_with_avg AS (
    SELECT
        mp.*,
        AVG(mp.monthly_amount) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount,
        RANK() OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.monthly_amount DESC
        ) AS month_rank
    FROM monthly_payments AS mp
    WHERE mp.payment_count >= 5
      AND mp.store_count >= 2
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
        GROUP_CONCAT(cs.category_name, ', ') AS main_categories
    FROM category_spending AS cs
    WHERE cs.cat_amount = (
        SELECT MAX(cat_amount)
        FROM category_spending
        WHERE customer_id = cs.customer_id AND month_start = cs.month_start
    )
    GROUP BY cs.customer_id, cs.month_start
)
SELECT
    strftime('%Y-%m', mwa.month_start) AS month,
    ROUND(mwa.monthly_amount, 2) AS total_amount,
    mwa.payment_count,
    ROUND(mwa.off_store_share, 4) AS off_store_share,
    ROUND(mwa.max_payment, 2) AS max_payment,
    mwa.month_rank,
    tc.main_categories
FROM monthly_with_avg AS mwa
JOIN top_categories AS tc ON tc.customer_id = mwa.customer_id AND tc.month_start = mwa.month_start
WHERE mwa.prev_avg_amount IS NOT NULL
  AND mwa.monthly_amount > 3.0 * mwa.prev_avg_amount
ORDER BY mwa.month_start, mwa.monthly_amount DESC;