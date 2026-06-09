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
        ) AS hist_avg_sum
    FROM monthly_stats AS ms
),
country_medians AS (
    SELECT
        c.h01 AS customer_id,
        cnt.c01 AS country_id,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ms.payment_count) OVER (PARTITION BY cnt.c01, ms.month) AS median_country_payment_count
    FROM monthly_stats AS ms
    JOIN cus AS c ON c.h01 = ms.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt ON cnt.c01 = ct.d03
),
flagged_customers AS (
    SELECT
        ch.*,
        cm.country_id,
        cm.median_country_payment_count
    FROM customer_history AS ch
    JOIN country_medians AS cm ON cm.customer_id = ch.customer_id
    WHERE ch.hist_avg_sum IS NOT NULL
      AND ch.monthly_sum > (ch.hist_avg_sum * 3)
      AND ch.payment_count > cm.median_country_payment_count
),
category_analysis AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month,
        SUM(CASE WHEN cat.g02 IN ('Action', 'New') THEN p.p05 ELSE 0 END) * 1.0 / NULLIF(SUM(p.p05), 0) AS action_new_share
    FROM pay AS p
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    JOIN flc AS fc ON fc.l01 = i.n02
    JOIN cat ON cat.g01 = fc.l02
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
)
SELECT
    fc.customer_id,
    fc.month,
    fc.payment_count,
    fc.monthly_sum,
    fc.max_payment,
    ca.action_new_share,
    RANK() OVER (PARTITION BY fc.country_id, fc.month ORDER BY fc.monthly_sum DESC) AS country_rank
FROM flagged_customers AS fc
JOIN category_analysis AS ca ON ca.customer_id = fc.customer_id AND ca.month = fc.month
ORDER BY fc.month DESC, country_rank ASC;