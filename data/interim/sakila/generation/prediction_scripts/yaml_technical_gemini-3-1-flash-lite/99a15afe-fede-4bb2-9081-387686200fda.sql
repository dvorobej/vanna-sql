WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS total_amount,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        SUM(CASE WHEN r.q05 > r.q02 THEN 1 ELSE 0 END) AS late_return_count,
        COUNT(r.q01) AS rental_count
    FROM pay p
    LEFT JOIN ren r ON p.p04 = r.q01
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_history AS (
    SELECT
        ms.*,
        AVG(ms.total_amount) OVER (
            PARTITION BY ms.customer_id 
            ORDER BY ms.payment_month 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount
    FROM monthly_stats ms
),
store_country_stats AS (
    SELECT
        c.h01 AS customer_id,
        c.h02 AS store_id,
        co.c01 AS country_id,
        co.c02 AS country_name,
        ct.d02 AS city_name
    FROM cus c
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ct ON a.e05 = ct.d01
    JOIN cnt co ON ct.d03 = co.c01
),
percentiles AS (
    SELECT
        sc.store_id,
        sc.country_id,
        ms.payment_month,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY ms.total_amount) OVER (
            PARTITION BY sc.store_id, sc.country_id, ms.payment_month
        ) AS p95_amount
    FROM monthly_stats ms
    JOIN store_country_stats sc ON ms.customer_id = sc.customer_id
),
ranked_data AS (
    SELECT
        ch.*,
        sc.country_name,
        sc.city_name,
        sc.store_id,
        RANK() OVER (
            PARTITION BY sc.store_id, ch.payment_month 
            ORDER BY ch.total_amount DESC
        ) AS store_rank,
        p.p95_amount
    FROM customer_history ch
    JOIN store_country_stats sc ON ch.customer_id = sc.customer_id
    JOIN percentiles p ON sc.store_id = p.store_id 
        AND sc.country_id = p.country_id 
        AND ch.payment_month = p.payment_month
)
SELECT
    c.h01,
    c.h03,
    c.h04,
    rd.country_name,
    rd.city_name,
    rd.store_id,
    rd.payment_month,
    rd.total_amount,
    rd.payment_count,
    rd.staff_count,
    CAST(rd.late_return_count AS REAL) / NULLIF(rd.rental_count, 0) AS late_return_share,
    rd.store_rank
FROM ranked_data rd
JOIN cus c ON rd.customer_id = c.h01
WHERE rd.prev_avg_amount IS NOT NULL
  AND rd.total_amount >= 3 * rd.prev_avg_amount
  AND rd.total_amount > rd.p95_amount;