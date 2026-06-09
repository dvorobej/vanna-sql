WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        c.h02 AS customer_store_id,
        cn.c01 AS country_id,
        cn.c02 AS country_name,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        SUM(CASE WHEN s.o07 <> c.h02 THEN 1 ELSE 0 END) * 1.0 / COUNT(p.p01) AS foreign_store_share
    FROM pay p
    JOIN cus c ON c.h01 = p.p02
    JOIN stf s ON s.o01 = p.p03
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ct ON ct.d01 = a.e05
    JOIN cnt cn ON cn.c01 = ct.d03
    GROUP BY p.p02, c.h02, cn.c01, cn.c02, strftime('%Y-%m', p.p06)
),
moving_avg AS (
    SELECT
        *,
        AVG(monthly_sum) OVER (
            PARTITION BY customer_id 
            ORDER BY payment_month 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS prev_2m_avg
    FROM monthly_stats
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
    FROM monthly_stats
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
    ms.customer_id,
    ms.payment_month,
    ms.monthly_sum,
    ms.payment_count,
    ms.distinct_staff_count,
    ms.foreign_store_share,
    RANK() OVER (
        PARTITION BY ms.country_id, ms.payment_month 
        ORDER BY ms.monthly_sum DESC
    ) AS country_rank
FROM monthly_stats ms
JOIN moving_avg ma ON ma.customer_id = ms.customer_id AND ma.payment_month = ms.payment_month
JOIN p95_thresholds p95 ON p95.country_id = ms.country_id AND p95.payment_month = ms.payment_month
WHERE ms.monthly_sum >= 3.0 * COALESCE(ma.prev_2m_avg, 0)
  AND ms.monthly_sum >= p95.p95_val
ORDER BY ms.payment_month, ms.country_id, country_rank;