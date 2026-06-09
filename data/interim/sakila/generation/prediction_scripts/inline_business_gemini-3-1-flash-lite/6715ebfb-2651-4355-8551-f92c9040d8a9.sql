WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(*) AS monthly_count,
        MAX(p.p05) AS max_payment,
        SUM(CASE WHEN c.g02 IN ('Action', 'New') THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS action_new_share
    FROM pay AS p
    JOIN ren AS r ON p.p04 = r.q01
    JOIN inv AS i ON r.q03 = i.n01
    JOIN flc AS fc ON i.n02 = fc.l01
    JOIN cat AS c ON fc.l02 = c.g01
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_history AS (
    SELECT
        customer_id,
        AVG(monthly_sum) AS avg_monthly_sum
    FROM monthly_customer_stats
    GROUP BY customer_id
),
country_stats AS (
    SELECT
        co.c01 AS country_id,
        mcs.payment_month,
        (SELECT AVG(cnt) FROM (SELECT COUNT(*) AS cnt FROM monthly_customer_stats GROUP BY customer_id, payment_month)) AS median_count_per_country
    FROM monthly_customer_stats mcs
    JOIN cus cu ON mcs.customer_id = cu.h01
    JOIN adr a ON cu.h06 = a.e01
    JOIN cty ci ON a.e05 = ci.d01
    JOIN cnt co ON ci.d03 = co.c01
    GROUP BY co.c01, mcs.payment_month
),
suspicious_cases AS (
    SELECT
        mcs.*,
        cu.h03 || ' ' || cu.h04 AS customer_name,
        co.c02 AS country_name,
        ci.d02 AS city_name,
        cu.h02 AS store_id,
        ch.avg_monthly_sum,
        cs.median_count_per_country
    FROM monthly_customer_stats mcs
    JOIN customer_history ch ON mcs.customer_id = ch.customer_id
    JOIN cus cu ON mcs.customer_id = cu.h01
    JOIN adr a ON cu.h06 = a.e01
    JOIN cty ci ON a.e05 = ci.d01
    JOIN cnt co ON ci.d03 = co.c01
    JOIN country_stats cs ON co.c01 = cs.country_id AND mcs.payment_month = cs.payment_month
    WHERE mcs.monthly_sum > ch.avg_monthly_sum * 2
      AND mcs.monthly_count > cs.median_count_per_country
),
ranked_suspicious AS (
    SELECT
        *,
        DENSE_RANK() OVER (PARTITION BY country_name ORDER BY monthly_sum DESC) AS country_rank
    FROM suspicious_cases
)
SELECT
    payment_month,
    customer_name,
    country_name,
    city_name,
    store_id,
    monthly_count,
    ROUND(monthly_sum, 2) AS monthly_sum,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(action_new_share, 4) AS action_new_share,
    country_rank
FROM ranked_suspicious
ORDER BY country_name, country_rank;