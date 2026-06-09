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
        ) AS avg_prev_amount
    FROM monthly_stats AS ms
),
country_median AS (
    SELECT
        c.c01 AS country_id,
        ms.month,
        (SELECT AVG(cnt) FROM (
            SELECT COUNT(*) AS cnt FROM monthly_stats ms2 
            JOIN cus c2 ON ms2.customer_id = c2.h01 
            JOIN adr a2 ON c2.h06 = a2.e01 
            JOIN cty ct2 ON a2.e05 = ct2.d01 
            WHERE ct2.d03 = c.c01 AND ms2.month = ms.month
            ORDER BY cnt LIMIT 2 - (SELECT COUNT(*) FROM monthly_stats) % 2 OFFSET (SELECT (COUNT(*) - 1) / 2 FROM monthly_stats)
        )) AS median_count
    FROM cnt c, monthly_stats ms
    GROUP BY c.c01, ms.month
),
category_share AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month,
        SUM(CASE WHEN cat.g02 IN ('Action', 'New') THEN p.p05 ELSE 0 END) * 1.0 / SUM(p.p05) AS cat_share
    FROM pay p
    JOIN ren r ON p.p04 = r.q01
    JOIN inv i ON r.q03 = i.n01
    JOIN flc f ON i.n02 = f.l01
    JOIN cat ON f.l02 = cat.g01
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
suspicious_cases AS (
    SELECT
        ch.*,
        c.h02 AS store_id,
        ct.d02 AS city,
        cnt.c02 AS country,
        cnt.c01 AS country_id,
        cs.cat_share
    FROM customer_history ch
    JOIN cus c ON ch.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ct ON a.e05 = ct.d01
    JOIN cnt ON ct.d03 = cnt.c01
    JOIN category_share cs ON ch.customer_id = cs.customer_id AND ch.month = cs.month
    JOIN country_median cm ON cnt.c01 = cm.country_id AND ch.month = cm.month
    WHERE ch.monthly_amount > 3 * ch.avg_prev_amount
      AND ch.monthly_count > cm.median_count
)
SELECT
    country,
    city,
    store_id,
    monthly_count,
    monthly_amount,
    max_payment,
    cat_share,
    RANK() OVER (PARTITION BY country_id ORDER BY monthly_amount DESC) AS country_rank
FROM suspicious_cases
ORDER BY country, country_rank;