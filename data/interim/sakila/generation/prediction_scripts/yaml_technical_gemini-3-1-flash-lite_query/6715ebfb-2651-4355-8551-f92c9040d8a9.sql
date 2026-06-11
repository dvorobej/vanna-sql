WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS monthly_count,
        MAX(p.p05) AS max_payment
    FROM pay AS p
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_history AS (
    SELECT
        ms.*,
        AVG(ms.monthly_amount) OVER (
            PARTITION BY ms.customer_id
            ORDER BY ms.month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS hist_avg_amount
    FROM monthly_stats AS ms
),
country_medians AS (
    SELECT
        c.country_id,
        ms.month,
        AVG(ms.monthly_count) AS median_count
    FROM (
        SELECT
            ms.customer_id,
            ms.month,
            ms.monthly_count,
            ROW_NUMBER() OVER (PARTITION BY ms.month, co.c01 ORDER BY ms.monthly_count) AS rn,
            COUNT(*) OVER (PARTITION BY ms.month, co.c01) AS cnt,
            co.c01 AS country_id
        FROM monthly_stats AS ms
        JOIN cus AS cu ON cu.h01 = ms.customer_id
        JOIN adr AS a ON a.e01 = cu.h06
        JOIN cty AS ci ON ci.d01 = a.e05
        JOIN cnt AS co ON co.c01 = ci.d03
    ) AS ms
    WHERE rn IN (CAST((cnt + 1) / 2 AS INT), CAST((cnt + 2) / 2 AS INT))
    GROUP BY country_id, month
),
category_share AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month,
        SUM(CASE WHEN cat.g02 IN ('Action', 'New') THEN p.p05 ELSE 0 END) * 1.0 / SUM(p.p05) AS action_new_share
    FROM pay AS p
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    JOIN flc AS fc ON fc.l01 = i.n02
    JOIN cat ON cat.g01 = fc.l02
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
suspicious_cases AS (
    SELECT
        ch.*,
        cu.h02 AS store_id,
        ci.d02 AS city,
        co.c02 AS country,
        co.c01 AS country_id,
        cs.action_new_share
    FROM customer_history AS ch
    JOIN cus AS cu ON cu.h01 = ch.customer_id
    JOIN adr AS a ON a.e01 = cu.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
    JOIN country_medians AS cm ON cm.country_id = co.c01 AND cm.month = ch.month
    LEFT JOIN category_share AS cs ON cs.customer_id = ch.customer_id AND cs.month = ch.month
    WHERE ch.hist_avg_amount > 0
      AND ch.monthly_amount > 3 * ch.hist_avg_amount
      AND ch.monthly_count > cm.median_count
)
SELECT
    country,
    city,
    store_id,
    month,
    monthly_count,
    monthly_amount,
    max_payment,
    COALESCE(action_new_share, 0) AS action_new_share,
    RANK() OVER (PARTITION BY country_id ORDER BY monthly_amount DESC) AS country_rank
FROM suspicious_cases
ORDER BY country, country_rank;