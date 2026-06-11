WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS total_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT s.o07) AS store_count,
        SUM(CASE WHEN s.o07 <> c.h02 THEN 1 ELSE 0 END) AS foreign_store_payment_count,
        GROUP_CONCAT(DISTINCT cat.g02) AS category_list
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN stf AS s ON s.o01 = p.p03
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    JOIN flc AS fc ON fc.l01 = i.n02
    JOIN cat ON cat.g01 = fc.l02
    JOIN adr AS ca ON ca.e01 = c.h06
    JOIN cty AS cty ON cty.d01 = ca.e05
    JOIN adr AS sa ON sa.e01 = (SELECT o04 FROM stf WHERE o07 = s.o07 LIMIT 1)
    JOIN cty AS scty ON scty.d01 = sa.e05
    WHERE cty.d03 <> scty.d03 OR cty.d01 <> sa.e05
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
monthly_with_avg AS (
    SELECT
        mp.*,
        AVG(mp.total_amount) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.payment_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount
    FROM monthly_payments AS mp
),
ranked_months AS (
    SELECT
        mwa.*,
        RANK() OVER (
            PARTITION BY mwa.customer_id
            ORDER BY mwa.total_amount DESC
        ) AS month_rank
    FROM monthly_with_avg AS mwa
)
SELECT
    rm.payment_month,
    rm.customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    ROUND(rm.total_amount, 2) AS total_amount,
    rm.payment_count,
    ROUND(rm.foreign_store_payment_count * 1.0 / rm.payment_count, 4) AS foreign_store_share,
    ROUND(rm.max_payment, 2) AS max_payment,
    rm.month_rank,
    rm.category_list
FROM ranked_months AS rm
JOIN cus AS c ON c.h01 = rm.customer_id
WHERE rm.prev_avg_amount IS NOT NULL
  AND rm.total_amount >= rm.prev_avg_amount * 3
  AND rm.payment_count >= 5
  AND rm.store_count > 1
ORDER BY rm.payment_month, rm.total_amount DESC;