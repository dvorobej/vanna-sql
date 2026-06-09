WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS total_amount,
        COUNT(p.p01) AS payment_count,
        MAX(p.p05) AS max_payment,
        SUM(CASE WHEN c.g02 = 'Action' THEN p.p05 ELSE 0 END) AS action_amount,
        SUM(CASE WHEN c.g02 = 'New' THEN p.p05 ELSE 0 END) AS new_amount
    FROM pay AS p
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    JOIN flc AS fc ON fc.l01 = i.n02
    JOIN cat AS c ON c.g01 = fc.l02
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_info AS (
    SELECT
        cu.h01 AS customer_id,
        cu.h03 || ' ' || cu.h04 AS customer_name,
        cn.c02 AS country,
        ct.d02 AS city,
        cu.h02 AS store_id,
        cn.c01 AS country_id
    FROM cus AS cu
    JOIN adr AS a ON a.e01 = cu.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS cn ON cn.c01 = ct.d03
),
ranked_data AS (
    SELECT
        ms.*,
        ci.customer_name,
        ci.country,
        ci.city,
        ci.store_id,
        RANK() OVER (PARTITION BY ci.country_id, ms.payment_month ORDER BY ms.total_amount DESC) AS country_rank
    FROM monthly_stats AS ms
    JOIN customer_info AS ci ON ci.customer_id = ms.customer_id
)
SELECT
    payment_month,
    customer_name,
    country,
    city,
    store_id,
    ROUND(total_amount, 2) AS total_amount,
    payment_count,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(action_amount / NULLIF(total_amount, 0), 4) AS action_share,
    ROUND(new_amount / NULLIF(total_amount, 0), 4) AS new_share,
    country_rank
FROM ranked_data
WHERE total_amount > 100 OR payment_count > 10
ORDER BY payment_month, country, country_rank;