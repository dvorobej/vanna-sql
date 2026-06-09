WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        SUM(CASE WHEN s.o07 <> c.h02 THEN 1.0 ELSE 0.0 END) / COUNT(*) AS foreign_store_share
    FROM pay p
    JOIN cus c ON c.h01 = p.p02
    JOIN stf s ON s.o01 = p.p03
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_context AS (
    SELECT
        c.h01 AS customer_id,
        c.h02 AS store_id,
        co.c01 AS country_id,
        co.c02 AS country_name
    FROM cus c
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ct ON ct.d01 = a.e05
    JOIN cnt co ON co.c01 = ct.d03
),
enriched_stats AS (
    SELECT
        ms.*,
        cc.country_id,
        cc.country_name,
        AVG(ms.monthly_sum) OVER (
            PARTITION BY ms.customer_id 
            ORDER BY ms.payment_month 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS moving_avg_2m,
        COUNT(ms.monthly_sum) OVER (
            PARTITION BY ms.customer_id 
            ORDER BY ms.payment_month 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS count_prev_months
    FROM monthly_stats ms
    JOIN customer_context cc ON cc.customer_id = ms.customer_id
),
country_percentiles AS (
    SELECT
        country_id,
        payment_month,
        monthly_sum,
        PERCENT_RANK() OVER (
            PARTITION BY country_id, payment_month 
            ORDER BY monthly_sum
        ) AS p_rank
    FROM enriched_stats
),
p95_thresholds AS (
    SELECT
        country_id,
        payment_month,
        MIN(monthly_sum) AS p95_val
    FROM country_percentiles
    WHERE p_rank >= 0.95
    GROUP BY country_id, payment_month
)
SELECT
    es.customer_id,
    es.payment_month,
    es.monthly_sum,
    es.payment_count,
    es.distinct_staff_count,
    ROUND(es.foreign_store_share, 4) AS foreign_store_share,
    RANK() OVER (
        PARTITION BY es.country_id, es.payment_month 
        ORDER BY es.monthly_sum DESC
    ) AS country_rank
FROM enriched_stats es
JOIN p95_thresholds p95 
  ON p95.country_id = es.country_id 
 AND p95.payment_month = es.payment_month
WHERE es.count_prev_months = 2
  AND es.monthly_sum >= 3.0 * es.moving_avg_2m
  AND es.monthly_sum >= p95.p95_val
ORDER BY es.payment_month, es.country_name, country_rank;