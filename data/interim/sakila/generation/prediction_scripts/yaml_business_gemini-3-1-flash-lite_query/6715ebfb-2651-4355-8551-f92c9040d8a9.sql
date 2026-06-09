WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        SUM(CASE WHEN cat.g02 IN ('Action', 'New') THEN p.p05 ELSE 0 END) AS action_new_amount
    FROM pay AS p
    LEFT JOIN ren AS r ON r.q01 = p.p04
    LEFT JOIN inv AS i ON i.n01 = r.q03
    LEFT JOIN flc AS fc ON fc.l01 = i.n02
    LEFT JOIN cat ON cat.g01 = fc.l02
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
        c.h01 AS customer_id,
        cn.c02 AS country_name,
        ct.d02 AS city_name,
        c.h02 AS store_id,
        cn.c01 AS country_id,
        (SELECT AVG(cnt) FROM (
            SELECT COUNT(*) AS cnt FROM monthly_customer_stats mcs2
            JOIN cus c2 ON c2.h01 = mcs2.customer_id
            JOIN adr a2 ON a2.e01 = c2.h06
            JOIN cty ct2 ON ct2.d01 = a2.e05
            WHERE ct2.d03 = cn.c01
            GROUP BY mcs2.customer_id
        )) AS country_median_payment_count
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS cn ON cn.c01 = ct.d03
),
suspicious_cases AS (
    SELECT
        ch.*,
        cmc.country_name,
        cmc.city_name,
        cmc.store_id,
        cmc.country_id
    FROM customer_history AS ch
    JOIN country_median_counts AS cmc ON cmc.customer_id = ch.customer_id
    WHERE ch.avg_prev_amount IS NOT NULL
      AND ch.monthly_amount > 3 * ch.avg_prev_amount
      AND ch.payment_count > cmc.country_median_payment_count
),
ranked_suspicious AS (
    SELECT
        *,
        DENSE_RANK() OVER (PARTITION BY country_id ORDER BY monthly_amount DESC) AS country_rank
    FROM suspicious_cases
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