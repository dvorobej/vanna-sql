WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month,
        SUM(p.p05) AS monthly_sum,
        COUNT(*) AS monthly_count
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
        ) AS hist_avg_sum
    FROM monthly_stats AS ms
),
country_median_count AS (
    SELECT
        c.c01 AS country_id,
        ms.month,
        (SELECT AVG(cnt) FROM (
            SELECT COUNT(*) AS cnt FROM monthly_stats ms2
            JOIN cus c2 ON ms2.customer_id = c2.h01
            JOIN adr a2 ON c2.h06 = a2.e01
            JOIN cty ct2 ON a2.e05 = ct2.d01
            WHERE ct2.d03 = c.c01 AND ms2.month = ms.month
            GROUP BY ms2.customer_id
        )) AS median_count
    FROM cnt c
    JOIN cty ct ON c.c01 = ct.d03
    JOIN adr a ON ct.d01 = a.e05
    JOIN cus cu ON a.e01 = cu.h06
    JOIN monthly_stats ms ON cu.h01 = ms.customer_id
    GROUP BY c.c01, ms.month
),
suspicious_cases AS (
    SELECT
        ch.*,
        cu.h02 AS store_id,
        ct.d02 AS city_name,
        cn.c02 AS country_name,
        cn.c01 AS country_id
    FROM customer_history ch
    JOIN cus cu ON ch.customer_id = cu.h01
    JOIN adr a ON cu.h06 = a.e01
    JOIN cty ct ON a.e05 = ct.d01
    JOIN cnt cn ON ct.d03 = cn.c01
    JOIN country_median_count cmc ON cn.c01 = cmc.country_id AND ch.month = cmc.month
    WHERE ch.hist_avg_sum > 0
      AND ch.monthly_sum > 3 * ch.hist_avg_sum
      AND ch.monthly_count > cmc.median_count
),
payment_details AS (
    SELECT
        sc.customer_id,
        sc.month,
        MAX(p.p05) AS max_payment,
        SUM(CASE WHEN cat.g02 IN ('Action', 'New') THEN p.p05 ELSE 0 END) / SUM(p.p05) AS action_new_share
    FROM suspicious_cases sc
    JOIN pay p ON sc.customer_id = p.p02 AND strftime('%Y-%m', p.p06) = sc.month
    LEFT JOIN ren r ON p.p04 = r.q01
    LEFT JOIN inv i ON r.q03 = i.n01
    LEFT JOIN flc fc ON i.n02 = fc.l01
    LEFT JOIN cat ON fc.l02 = cat.g01
    GROUP BY sc.customer_id, sc.month
)
SELECT
    sc.country_name,
    sc.city_name,
    sc.store_id,
    sc.monthly_count,
    sc.monthly_sum,
    pd.max_payment,
    pd.action_new_share,
    RANK() OVER (PARTITION BY sc.country_id ORDER BY sc.monthly_sum DESC) AS country_rank
FROM suspicious_cases sc
JOIN payment_details pd ON sc.customer_id = pd.customer_id AND sc.month = pd.month
ORDER BY country_rank;