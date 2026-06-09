WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS payment_count,
        MAX(p.p05) AS max_payment
    FROM pay AS p
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_history AS (
    SELECT
        ms.*,
        AVG(ms.monthly_sum) OVER (
            PARTITION BY ms.customer_id
            ORDER BY ms.month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS historical_avg_sum
    FROM monthly_stats AS ms
),
country_medians AS (
    SELECT
        c.c01 AS country_id,
        ms.month,
        (SELECT AVG(cnt_val) FROM (
            SELECT COUNT(p01) AS cnt_val FROM pay p2
            JOIN cus c2 ON p2.p02 = c2.h01
            JOIN adr a2 ON c2.h06 = a2.e01
            JOIN cty ct2 ON a2.e05 = ct2.d01
            WHERE ct2.d03 = c.c01 AND strftime('%Y-%m', p2.p06) = ms.month
            GROUP BY p2.p02
        )) AS median_payment_count
    FROM cnt c
    JOIN monthly_stats ms
),
filtered_customers AS (
    SELECT
        ch.*,
        c.h02 AS store_id,
        ct.d03 AS country_id,
        ct.d01 AS city_id
    FROM customer_history ch
    JOIN cus c ON ch.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ct ON a.e05 = ct.d01
    JOIN country_medians cm ON ct.d03 = cm.country_id AND ch.month = cm.month
    WHERE ch.historical_avg_sum IS NOT NULL
      AND ch.monthly_sum > 3 * ch.historical_avg_sum
      AND ch.payment_count > cm.median_payment_count
),
category_analysis AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month,
        SUM(CASE WHEN cat.g02 IN ('Action', 'New') THEN p.p05 ELSE 0 END) * 1.0 / SUM(p.p05) AS action_new_share
    FROM pay p
    JOIN ren r ON p.p04 = r.q01
    JOIN inv i ON r.q03 = i.n01
    JOIN flc ON i.n02 = flc.l01
    JOIN cat ON flc.l02 = cat.g01
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
)
SELECT
    fc.customer_id,
    fc.month,
    fc.payment_count,
    fc.monthly_sum,
    fc.max_payment,
    ca.action_new_share,
    RANK() OVER (PARTITION BY fc.city_id, fc.month ORDER BY fc.monthly_sum DESC) AS city_rank
FROM filtered_customers fc
LEFT JOIN category_analysis ca ON fc.customer_id = ca.customer_id AND fc.month = ca.month
ORDER BY fc.month, fc.monthly_sum DESC;