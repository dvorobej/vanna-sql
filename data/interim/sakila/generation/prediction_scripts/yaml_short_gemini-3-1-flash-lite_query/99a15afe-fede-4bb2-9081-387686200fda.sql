WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS monthly_amount,
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
        mcs.*,
        AVG(mcs.monthly_amount) OVER (
            PARTITION BY mcs.customer_id 
            ORDER BY mcs.month_start 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount
    FROM monthly_customer_stats mcs
),
store_country_stats AS (
    SELECT
        mcs.month_start,
        c.h02 AS store_id,
        co.c01 AS country_id,
        mcs.monthly_amount,
        PERCENT_RANK() OVER (
            PARTITION BY mcs.month_start, c.h02, co.c01 
            ORDER BY mcs.monthly_amount
        ) AS p_rank,
        RANK() OVER (
            PARTITION BY mcs.month_start, c.h02 
            ORDER BY mcs.monthly_amount DESC
        ) AS store_rank
    FROM monthly_customer_stats mcs
    JOIN cus c ON mcs.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ci ON a.e05 = ci.d01
    JOIN cnt co ON ci.d03 = co.c01
)
SELECT
    ch.customer_id,
    co.c02 AS country,
    ci.d02 AS city,
    c.h02 AS store_id,
    ch.month_start AS month,
    ROUND(ch.monthly_amount, 2) AS total_amount,
    ch.payment_count,
    ch.staff_count,
    ROUND(ch.late_return_share, 4) AS late_return_share,
    scs.store_rank
FROM customer_history ch
JOIN cus c ON ch.customer_id = c.h01
JOIN adr a ON c.h06 = a.e01
JOIN cty ci ON a.e05 = ci.d01
JOIN cnt co ON ci.d03 = co.c01
JOIN store_country_stats scs ON ch.customer_id = (
    SELECT customer_id FROM monthly_customer_stats WHERE monthly_amount = scs.monthly_amount LIMIT 1
) AND ch.month_start = scs.month_start
WHERE ch.prev_avg_amount IS NOT NULL
  AND ch.monthly_amount >= 3 * ch.prev_avg_amount
  AND scs.p_rank >= 0.95
ORDER BY ch.month_start, ch.monthly_amount DESC;