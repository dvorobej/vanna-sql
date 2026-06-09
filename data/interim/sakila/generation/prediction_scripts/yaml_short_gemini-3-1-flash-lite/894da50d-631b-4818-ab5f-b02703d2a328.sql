WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS total_amount,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT s.o07) AS store_count,
        SUM(CASE WHEN s.o07 <> c.h02 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS off_store_share,
        GROUP_CONCAT(DISTINCT cat.g02) AS categories
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN stf AS s ON s.o01 = p.p03
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    JOIN flc AS fc ON fc.l01 = i.n02
    JOIN cat ON cat.g01 = fc.l02
    JOIN adr AS ca ON ca.e01 = c.h06
    JOIN adr AS sa ON sa.e01 = s.o04
    WHERE ca.e05 <> sa.e05 OR ca.e06 <> sa.e06
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
        RANK() OVER (PARTITION BY mwa.customer_id ORDER BY mwa.total_amount DESC) AS month_rank
    FROM monthly_with_avg AS mwa
    WHERE mwa.prev_avg_amount IS NOT NULL
      AND mwa.total_amount >= 3.0 * mwa.prev_avg_amount
      AND mwa.payment_count >= 5
      AND mwa.store_count > 1
)
SELECT
    rm.payment_month,
    c.h03 || ' ' || c.h04 AS customer_name,
    rm.total_amount,
    rm.payment_count,
    ROUND(rm.off_store_share, 4) AS off_store_share,
    rm.max_payment,
    rm.month_rank,
    rm.categories
FROM ranked_months AS rm
JOIN cus AS c ON c.h01 = rm.customer_id
ORDER BY rm.total_amount DESC;