WITH monthly_stats AS (
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
customer_history AS (
    SELECT
        ms.*,
        AVG(ms.total_amount) OVER (
            PARTITION BY ms.customer_id 
            ORDER BY ms.month_start 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount,
        c.h02 AS store_id,
        co.c02 AS country,
        ci.d02 AS city
    FROM monthly_stats ms
    JOIN cus c ON ms.customer_id = c.h01
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
    FROM customer_history
),
p95_thresholds AS (
    SELECT store_id, country, month_start, MAX(total_amount) as p95_val
    FROM store_country_percentiles
    WHERE p_rank <= 0.95
    GROUP BY store_id, country, month_start
),
ranked_customers AS (
    SELECT
        ch.*,
        RANK() OVER (
            PARTITION BY ch.store_id, ch.month_start 
            ORDER BY ch.total_amount DESC
        ) AS store_rank
    FROM customer_history ch
    JOIN p95_thresholds p95 
      ON ch.store_id = p95.store_id 
      AND ch.country = p95.country 
      AND ch.month_start = p95.month_start
    WHERE ch.prev_avg_amount IS NOT NULL
      AND ch.total_amount >= 3 * ch.prev_avg_amount
      AND ch.total_amount > p95.p95_val
)
SELECT
    ch.customer_id,
    ch.country,
    ch.city,
    ch.store_id,
    strftime('%Y-%m', ch.month_start) AS month,
    ROUND(ch.total_amount, 2) AS total_amount,
    ch.payment_count,
    ch.staff_count,
    ROUND(ch.late_return_share, 4) AS late_return_share,
    rc.store_rank
FROM customer_history ch
JOIN ranked_customers rc 
  ON ch.customer_id = rc.customer_id 
  AND ch.month_start = rc.month_start
ORDER BY ch.month_start, ch.store_id, rc.store_rank;