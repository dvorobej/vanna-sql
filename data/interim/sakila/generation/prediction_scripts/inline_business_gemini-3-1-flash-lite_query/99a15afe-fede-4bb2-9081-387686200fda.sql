WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS total_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        SUM(CASE WHEN r.q05 > date(r.q02, '+' || f.i07 || ' days') THEN 1.0 ELSE 0.0 END) / COUNT(*) AS late_return_share
    FROM pay p
    JOIN ren r ON p.p04 = r.q01
    JOIN inv i ON r.q03 = i.n01
    JOIN flm f ON i.n02 = f.i01
    GROUP BY p.p02, date(p.p06, 'start of month')
),
customer_stats AS (
    SELECT
        mp.*,
        c.h02 AS store_id,
        co.c02 AS country,
        ci.d02 AS city,
        AVG(mp.total_amount) OVER (
            PARTITION BY mp.customer_id 
            ORDER BY mp.month_start 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount,
        COUNT(*) OVER (
            PARTITION BY mp.customer_id 
            ORDER BY mp.month_start 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS history_count
    FROM monthly_payments mp
    JOIN cus c ON mp.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ci ON a.e05 = ci.d01
    JOIN cnt co ON ci.d03 = co.c01
),
store_country_percentiles AS (
    SELECT
        store_id,
        country,
        month_start,
        total_amount,
        PERCENT_RANK() OVER (
            PARTITION BY store_id, country, month_start 
            ORDER BY total_amount
        ) AS p_rank
    FROM customer_stats
),
p95_thresholds AS (
    SELECT store_id, country, month_start, MAX(total_amount) as p95_val
    FROM store_country_percentiles
    WHERE p_rank <= 0.95
    GROUP BY store_id, country, month_start
),
ranked_customers AS (
    SELECT
        cs.*,
        RANK() OVER (
            PARTITION BY cs.store_id, cs.month_start 
            ORDER BY cs.total_amount DESC
        ) AS store_rank
    FROM customer_stats cs
    JOIN p95_thresholds p95 
      ON cs.store_id = p95.store_id 
      AND cs.country = p95.country 
      AND cs.month_start = p95.month_start
    WHERE cs.history_count > 0
      AND cs.total_amount >= 3 * cs.prev_avg_amount
      AND cs.total_amount > p95.p95_val
)
SELECT
    customer_id,
    country,
    city,
    store_id,
    strftime('%Y-%m', month_start) AS month,
    ROUND(total_amount, 2) AS total_amount,
    payment_count,
    staff_count,
    ROUND(late_return_share, 4) AS late_return_share,
    store_rank
FROM ranked_customers
ORDER BY month, store_id, store_rank;