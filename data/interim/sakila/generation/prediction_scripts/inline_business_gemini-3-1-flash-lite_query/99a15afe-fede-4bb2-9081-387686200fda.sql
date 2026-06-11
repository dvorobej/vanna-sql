WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        SUM(CASE WHEN r.q05 > date(r.q02, '+' || f.i07 || ' days') THEN 1.0 ELSE 0.0 END) / COUNT(*) AS late_return_share,
        c.h02 AS store_id,
        ct.d03 AS country_id
    FROM pay p
    JOIN ren r ON p.p04 = r.q01
    JOIN inv i ON r.q03 = i.n01
    JOIN flm f ON i.n02 = f.i01
    JOIN cus c ON p.p02 = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ct ON a.e05 = ct.d01
    GROUP BY p.p02, date(p.p06, 'start of month'), c.h02, ct.d03
),
history_stats AS (
    SELECT
        *,
        AVG(monthly_amount) OVER (
            PARTITION BY customer_id 
            ORDER BY month_start 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount
    FROM monthly_customer_stats
),
store_country_percentiles AS (
    SELECT
        store_id,
        country_id,
        month_start,
        monthly_amount,
        PERCENT_RANK() OVER (
            PARTITION BY store_id, country_id, month_start 
            ORDER BY monthly_amount
        ) AS p_rank
    FROM monthly_customer_stats
),
p95_thresholds AS (
    SELECT
        store_id,
        country_id,
        month_start,
        MAX(CASE WHEN p_rank <= 0.95 THEN monthly_amount END) AS p95_amount
    FROM store_country_percentiles
    GROUP BY store_id, country_id, month_start
)
SELECT
    h.customer_id,
    co.c02 AS country,
    ct.d02 AS city,
    h.store_id,
    h.month_start,
    h.monthly_amount,
    h.payment_count,
    h.staff_count,
    h.late_return_share,
    RANK() OVER (
        PARTITION BY h.store_id, h.month_start 
        ORDER BY h.monthly_amount DESC
    ) AS store_rank
FROM history_stats h
JOIN p95_thresholds p ON h.store_id = p.store_id 
    AND h.country_id = p.country_id 
    AND h.month_start = p.month_start
JOIN cus c ON h.customer_id = c.h01
JOIN adr a ON c.h06 = a.e01
JOIN cty ct ON a.e05 = ct.d01
JOIN cnt co ON ct.d03 = co.c01
WHERE h.prev_avg_amount IS NOT NULL
  AND h.monthly_amount >= 3 * h.prev_avg_amount
  AND h.monthly_amount > p.p95_amount
ORDER BY h.month_start, h.store_id, h.monthly_amount DESC;