WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT s.o07) AS store_count,
        SUM(CASE WHEN a_cus.e05 <> a_sto.e05 OR cnt_cus.c01 <> cnt_sto.c01 THEN 1 ELSE 0 END) AS foreign_store_payment_count
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN adr AS a_cus ON a_cus.e01 = c.h06
    JOIN cty AS ct_cus ON ct_cus.d01 = a_cus.e05
    JOIN cnt AS cnt_cus ON cnt_cus.c01 = ct_cus.d03
    JOIN stf AS s ON s.o01 = p.p03
    JOIN sto AS st ON st.j01 = s.o07
    JOIN adr AS a_sto ON a_sto.e01 = st.j03
    JOIN cty AS ct_sto ON ct_sto.d01 = a_sto.e05
    JOIN cnt AS cnt_sto ON cnt_sto.c01 = ct_sto.d03
    WHERE p.p04 IS NOT NULL
    GROUP BY p.p02, date(p.p06, 'start of month')
),
monthly_with_history AS (
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
    JOIN flc ON flc.l01 = i.n02
    JOIN cat ON cat.g01 = flc.l02
    GROUP BY p.p02, date(p.p06, 'start of month'), cat.g02
),
top_categories AS (
    SELECT
        cs.customer_id,
        cs.month_start,
        GROUP_CONCAT(cs.category_name, ', ') AS top_categories_list
    FROM category_spending AS cs
    WHERE cs.cat_amount = (
        SELECT MAX(cat_amount)
        FROM category_spending
        WHERE customer_id = cs.customer_id AND month_start = cs.month_start
    )
    GROUP BY cs.customer_id, cs.month_start
)
SELECT
    strftime('%Y-%m', mwh.month_start) AS payment_month,
    mwh.monthly_amount,
    mwh.payment_count,
    ROUND(CAST(mwh.foreign_store_payment_count AS REAL) / mwh.payment_count, 4) AS foreign_store_share,
    mwh.max_payment,
    mwh.month_rank,
    tc.top_categories_list
FROM monthly_with_history AS mwh
JOIN top_categories AS tc ON tc.customer_id = mwh.customer_id AND tc.month_start = mwh.month_start
WHERE mwh.prev_avg_amount IS NOT NULL
  AND mwh.monthly_amount > mwh.prev_avg_amount * 3
  AND mwh.payment_count >= 5
  AND mwh.store_count >= 2
  AND mwh.foreign_store_payment_count > 0
ORDER BY mwh.month_start, mwh.monthly_amount DESC;