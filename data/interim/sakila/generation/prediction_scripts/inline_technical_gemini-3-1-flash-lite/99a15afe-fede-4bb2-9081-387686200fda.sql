WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        SUM(CASE WHEN r.q05 > r.q02 THEN 1 ELSE 0 END) AS late_returns,
        COUNT(r.q01) AS total_rentals
    FROM pay p
    LEFT JOIN ren r ON p.p04 = r.q01
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_history AS (
    SELECT
        ms.*,
        AVG(ms.monthly_sum) OVER (
            PARTITION BY ms.customer_id 
            ORDER BY ms.payment_month 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_sum
    FROM monthly_stats ms
),
store_country_stats AS (
    SELECT
        ms.payment_month,
        c.h02 AS store_id,
        cnt.c01 AS country_id,
        ms.monthly_sum
    FROM monthly_stats ms
    JOIN cus c ON ms.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ct ON a.e05 = ct.d01
    JOIN cnt ON ct.d03 = cnt.c01
),
percentiles AS (
    SELECT
        payment_month,
        store_id,
        country_id,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY monthly_sum) OVER (PARTITION BY payment_month, store_id, country_id) AS p95_sum
    FROM store_country_stats
),
ranked_data AS (
    SELECT
        ch.*,
        c.h03,
        c.h04,
        c.h02 AS store_id,
        cnt.c02 AS country_name,
        ct.d02 AS city_name,
        cnt.c01 AS country_id,
        RANK() OVER (PARTITION BY c.h02, ch.payment_month ORDER BY ch.monthly_sum DESC) AS store_rank,
        p.p95_sum
    FROM customer_history ch
    JOIN cus c ON ch.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ct ON a.e05 = ct.d01
    JOIN cnt ON ct.d03 = cnt.c01
    JOIN percentiles p ON ch.payment_month = p.payment_month AND c.h02 = p.store_id AND cnt.c01 = p.country_id
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
    CAST(late_returns AS REAL) / NULLIF(total_rentals, 0) AS late_return_share,
    store_rank
FROM ranked_data
WHERE monthly_sum > 3 * prev_avg_sum
  AND monthly_sum > p95_sum
ORDER BY payment_month, store_id, store_rank;