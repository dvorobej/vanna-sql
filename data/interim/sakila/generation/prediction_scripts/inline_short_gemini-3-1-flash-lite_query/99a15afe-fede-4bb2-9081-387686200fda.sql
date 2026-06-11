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
        ct.d02 AS city,
        AVG(mp.total_amount) OVER (
            PARTITION BY mp.customer_id 
            ORDER BY mp.month_start 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount,
        COUNT(*) OVER (
            PARTITION BY mp.customer_id 
            ORDER BY mp.month_start 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_months_count
    FROM monthly_payments mp
    JOIN cus c ON mp.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ct ON a.e05 = ct.d01
    JOIN cnt co ON ct.d03 = co.c01
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
    SELECT
        store_id,
        country,
        month_start,
        MAX(CASE WHEN p_rank <= 0.95 THEN total_amount END) AS p95_amount
    FROM store_country_percentiles
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
)
SELECT
    rc.customer_id,
    rc.country,
    rc.city,
    rc.store_id,
    strftime('%Y-%m', rc.month_start) AS payment_month,
    ROUND(rc.total_amount, 2) AS total_amount,
    rc.payment_count,
    rc.staff_count,
    ROUND(rc.late_return_share, 4) AS late_return_share,
    rc.store_rank
FROM ranked_customers rc
JOIN p95_thresholds p95 
  ON rc.store_id = p95.store_id 
  AND rc.country = p95.country 
  AND rc.month_start = p95.month_start
WHERE rc.prev_months_count > 0
  AND rc.total_amount >= 3 * rc.prev_avg_amount
  AND rc.total_amount > p95.p95_amount
ORDER BY rc.month_start, rc.country, rc.store_id, rc.store_rank;