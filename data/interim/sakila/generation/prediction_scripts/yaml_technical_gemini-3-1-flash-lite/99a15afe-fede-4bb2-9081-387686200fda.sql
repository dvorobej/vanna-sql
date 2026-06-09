WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        SUM(CASE WHEN r.q05 > r.q02 THEN 1 ELSE 0 END) * 1.0 / COUNT(p.p01) AS overdue_share
    FROM pay p
    LEFT JOIN ren r ON r.q01 = p.p04
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_history AS (
    SELECT
        *,
        AVG(monthly_sum) OVER (
            PARTITION BY customer_id 
            ORDER BY payment_month 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_sum
    FROM monthly_stats
),
store_country_stats AS (
    SELECT
        c.h01 AS customer_id,
        c.h02 AS store_id,
        co.c01 AS country_id,
        co.c02 AS country_name,
        ct.d02 AS city_name,
        c.h03,
        c.h04
    FROM cus c
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ct ON ct.d01 = a.e05
    JOIN cnt co ON co.c01 = ct.d03
),
percentiles AS (
    SELECT
        ms.payment_month,
        sc.store_id,
        sc.country_id,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY ms.monthly_sum) OVER (
            PARTITION BY ms.payment_month, sc.store_id, sc.country_id
        ) AS p95_sum
    FROM monthly_stats ms
    JOIN store_country_stats sc ON sc.customer_id = ms.customer_id
),
ranked_data AS (
    SELECT
        ch.*,
        sc.h03,
        sc.h04,
        sc.country_name,
        sc.city_name,
        sc.store_id,
        RANK() OVER (
            PARTITION BY sc.store_id, ch.payment_month 
            ORDER BY ch.monthly_sum DESC
        ) AS store_rank
    FROM customer_history ch
    JOIN store_country_stats sc ON sc.customer_id = ch.customer_id
    JOIN percentiles p ON p.payment_month = ch.payment_month 
                       AND p.store_id = sc.store_id 
                       AND p.country_id = sc.country_id
    WHERE ch.prev_avg_sum IS NOT NULL
      AND ch.monthly_sum >= 3 * ch.prev_avg_sum
      AND ch.monthly_sum >= p.p95_sum
)
SELECT
    customer_id,
    h03,
    h04,
    country_name,
    city_name,
    store_id,
    payment_month,
    monthly_sum,
    payment_count,
    staff_count,
    overdue_share,
    store_rank
FROM ranked_data
ORDER BY payment_month, store_id, store_rank;