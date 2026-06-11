WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS total_amount,
        MAX(p.p05) AS max_payment,
        SUM(CASE WHEN c.g02 = 'Action' THEN 1 ELSE 0 END) AS action_count,
        SUM(CASE WHEN c.g02 = 'New' THEN 1 ELSE 0 END) AS new_count
    FROM pay AS p
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    JOIN flc AS fc ON fc.l01 = i.n02
    JOIN cat AS c ON c.g01 = fc.l02
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_details AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        co.c02 AS country,
        ct.d02 AS city,
        s.j01 AS store_id
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ct.d03
    JOIN sto AS s ON s.j01 = c.h02
),
ranked_data AS (
    SELECT
        ms.*,
        cd.customer_name,
        cd.country,
        cd.city,
        cd.store_id,
        RANK() OVER (PARTITION BY cd.country, ms.payment_month ORDER BY ms.total_amount DESC) AS country_rank
    FROM monthly_stats ms
    JOIN customer_details cd ON cd.customer_id = ms.customer_id
)
SELECT
    payment_month,
    customer_name,
    country,
    city,
    store_id,
    total_amount,
    payment_count,
    max_payment,
    ROUND(CAST(action_count AS REAL) / payment_count, 2) AS action_share,
    ROUND(CAST(new_count AS REAL) / payment_count, 2) AS new_share,
    country_rank
FROM ranked_data
WHERE total_amount > 100 OR payment_count > 10
ORDER BY payment_month, country, country_rank;