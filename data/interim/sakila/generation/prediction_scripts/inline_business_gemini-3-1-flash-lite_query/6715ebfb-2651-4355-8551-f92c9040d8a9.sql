WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        SUM(CASE WHEN c.g02 IN ('Action', 'New') THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS action_new_share
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
        ) AS avg_prev_amount
    FROM monthly_customer_stats AS mcs
),
country_median_counts AS (
    SELECT
        c.h01,
        ct.d03 AS country_id,
        (SELECT AVG(cnt) FROM (
            SELECT COUNT(*) AS cnt FROM monthly_customer_stats mcs2
            JOIN cus c2 ON mcs2.customer_id = c2.h01
            JOIN adr a2 ON c2.h06 = a2.e01
            JOIN cty ct2 ON a2.e05 = ct2.d01
            WHERE ct2.d03 = ct.d03
            GROUP BY mcs2.customer_id, mcs2.payment_month
        )) AS country_median_payment_count
    FROM cus c
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ct ON a.e05 = ct.d01
),
suspicious_cases AS (
    SELECT
        ch.*,
        c.h02 AS store_id,
        cnt.c02 AS country_name,
        ct.d02 AS city_name,
        cmc.country_median_payment_count
    FROM customer_history AS ch
    JOIN cus AS c ON ch.customer_id = c.h01
    JOIN adr AS a ON c.h06 = a.e01
    JOIN cty AS ct ON a.e05 = ct.d01
    JOIN cnt AS cnt ON ct.d03 = cnt.c01
    JOIN country_median_counts AS cmc ON ch.customer_id = cmc.h01
    WHERE ch.avg_prev_amount > 0
      AND ch.monthly_amount > 3 * ch.avg_prev_amount
      AND ch.payment_count > cmc.country_median_payment_count
),
ranked_suspicious AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY country_name ORDER BY monthly_amount DESC) AS country_rank
    FROM suspicious_cases
)
SELECT
    payment_month,
    country_name,
    city_name,
    store_id,
    payment_count,
    ROUND(monthly_amount, 2) AS total_amount,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(action_new_share, 4) AS action_new_share,
    country_rank
FROM ranked_suspicious
ORDER BY country_name, country_rank;