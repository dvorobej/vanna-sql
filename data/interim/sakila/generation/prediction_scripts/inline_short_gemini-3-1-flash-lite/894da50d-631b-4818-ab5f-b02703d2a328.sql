WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS total_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT s.o07) AS store_count,
        SUM(CASE WHEN a_cus.e05 <> a_stf.e05 OR cnt_cus.c01 <> cnt_stf.c01 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS foreign_store_share
    FROM pay AS p
    JOIN stf AS s ON p.p03 = s.o01
    JOIN cus AS c ON p.p02 = c.h01
    JOIN adr AS a_cus ON c.h06 = a_cus.e01
    JOIN cty AS cty_cus ON a_cus.e05 = cty_cus.d01
    JOIN cnt AS cnt_cus ON cty_cus.d03 = cnt_cus.c01
    JOIN adr AS a_stf ON s.o04 = a_stf.e01
    JOIN cty AS cty_stf ON a_stf.e05 = cty_stf.d01
    JOIN cnt AS cnt_stf ON cty_stf.d03 = cnt_stf.c01
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
monthly_history AS (
    SELECT
        ms.*,
        AVG(ms.total_amount) OVER (
            PARTITION BY ms.customer_id 
            ORDER BY ms.payment_month 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount
    FROM monthly_stats AS ms
),
customer_categories AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        GROUP_CONCAT(DISTINCT cat.g02) AS category_list
    FROM pay AS p
    JOIN ren AS r ON p.p04 = r.q01
    JOIN inv AS i ON r.q03 = i.n01
    JOIN flc AS fc ON i.n02 = fc.l01
    JOIN cat ON fc.l02 = cat.g01
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
)
SELECT
    m.payment_month,
    c.h03 || ' ' || c.h04 AS customer_name,
    m.total_amount,
    m.payment_count,
    m.foreign_store_share,
    m.max_payment,
    RANK() OVER (PARTITION BY m.customer_id ORDER BY m.payment_month) AS month_rank,
    cc.category_list
FROM monthly_history AS m
JOIN cus AS c ON m.customer_id = c.h01
JOIN customer_categories AS cc ON m.customer_id = cc.customer_id AND m.payment_month = cc.payment_month
WHERE m.prev_avg_amount IS NOT NULL
  AND m.total_amount >= 3.0 * m.prev_avg_amount
  AND m.payment_count >= 5
  AND m.store_count > 1
  AND m.foreign_store_share > 0
ORDER BY m.payment_month DESC, m.total_amount DESC;