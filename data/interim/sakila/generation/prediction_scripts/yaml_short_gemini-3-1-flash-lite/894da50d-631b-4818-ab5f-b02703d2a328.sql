WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS total_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT s.o07) AS store_count,
        GROUP_CONCAT(DISTINCT cat.g02) AS category_list
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    LEFT JOIN ren AS r ON r.q01 = p.p04
    LEFT JOIN inv AS i ON i.n01 = r.q03
    LEFT JOIN flc AS fc ON fc.l01 = i.n02
    LEFT JOIN cat ON cat.g01 = fc.l02
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        cty.d02 AS city_name,
        cnt.c02 AS country_name,
        c.h02 AS home_store_id
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
monthly_stats AS (
    SELECT
        mp.*,
        cg.city_name,
        cg.country_name,
        AVG(mp.total_amount) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.payment_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount,
        RANK() OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.total_amount DESC
        ) AS month_rank
    FROM monthly_payments AS mp
    JOIN customer_geo AS cg ON cg.customer_id = mp.customer_id
    WHERE mp.payment_count >= 5
      AND mp.store_count >= 2
),
off_store_payments AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(CASE WHEN s.o07 <> cg.home_store_id THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS off_store_share
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    JOIN customer_geo AS cg ON cg.customer_id = p.p02
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
)
SELECT
    ms.payment_month,
    ms.customer_id,
    ms.country_name,
    ms.city_name,
    ROUND(ms.total_amount, 2) AS total_amount,
    ms.payment_count,
    ROUND(osp.off_store_share, 4) AS off_store_share,
    ROUND(ms.max_payment, 2) AS max_payment,
    ms.month_rank,
    ms.category_list
FROM monthly_stats AS ms
JOIN off_store_payments AS osp 
    ON osp.customer_id = ms.customer_id 
    AND osp.payment_month = ms.payment_month
WHERE ms.prev_avg_amount > 0
  AND ms.total_amount >= 3.0 * ms.prev_avg_amount
ORDER BY ms.payment_month, ms.total_amount DESC;