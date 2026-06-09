WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        SUM(CASE WHEN c.g02 IN ('Action', 'New') THEN p.p05 ELSE 0 END) AS action_new_amount
    FROM pay AS p
    LEFT JOIN ren AS r ON p.p04 = r.q01
    LEFT JOIN inv AS i ON r.q03 = i.n01
    LEFT JOIN flc AS fc ON i.n02 = fc.l01
    LEFT JOIN cat AS c ON fc.l02 = c.g01
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_history AS (
    SELECT
        mcs.*,
        AVG(mcs.monthly_amount) OVER (
            PARTITION BY mcs.customer_id 
            ORDER BY mcs.payment_month 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS hist_avg_amount
    FROM monthly_customer_stats AS mcs
),
country_median_counts AS (
    SELECT
        cu.h01 AS customer_id,
        co.c01 AS country_id,
        co.c02 AS country_name,
        ct.d02 AS city_name,
        cu.h02 AS store_id,
        (SELECT AVG(m.payment_count) FROM (
            SELECT payment_count FROM monthly_customer_stats AS mcs2
            JOIN cus AS cu2 ON mcs2.customer_id = cu2.h01
            JOIN adr AS a2 ON cu2.h06 = a2.e01
            JOIN cty AS ct2 ON a2.e05 = ct2.d01
            WHERE ct2.d03 = co.c01
            ORDER BY payment_count LIMIT 2 - (COUNT(*) % 2) OFFSET (COUNT(*) - 1) / 2
        )) AS country_median_count
    FROM cus AS cu
    JOIN adr AS a ON cu.h06 = a.e01
    JOIN cty AS ct ON a.e05 = ct.d01
    JOIN cnt AS co ON ct.d03 = co.c01
),
suspicious_clients AS (
    SELECT
        ch.*,
        cmc.country_name,
        cmc.city_name,
        cmc.store_id,
        cmc.country_median_count
    FROM customer_history AS ch
    JOIN country_median_counts AS cmc ON ch.customer_id = cmc.customer_id
    WHERE ch.hist_avg_amount IS NOT NULL
      AND ch.monthly_amount > 3 * ch.hist_avg_amount
      AND ch.payment_count > cmc.country_median_count
),
ranked_suspicious AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY country_name ORDER BY monthly_amount DESC) AS country_rank
    FROM suspicious_clients
)
SELECT
    country_name,
    city_name,
    store_id,
    payment_month,
    payment_count,
    ROUND(monthly_amount, 2) AS total_amount,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(action_new_amount / NULLIF(monthly_amount, 0), 4) AS action_new_share,
    country_rank
FROM ranked_suspicious
ORDER BY country_name, country_rank;