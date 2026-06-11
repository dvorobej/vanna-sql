WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS total_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        SUM(CASE WHEN r.q05 > date(r.q02, '+' || f.i07 || ' days') THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS late_return_share
    FROM pay p
    JOIN ren r ON r.q01 = p.p04
    JOIN inv i ON i.n01 = r.q03
    JOIN flm f ON f.i01 = i.n02
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_history AS (
    SELECT
        mcs.*,
        AVG(total_amount) OVER (
            PARTITION BY customer_id 
            ORDER BY payment_month 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount
    FROM monthly_customer_stats mcs
),
store_country_stats AS (
    SELECT
        mcs.payment_month,
        c.h02 AS store_id,
        cnt.c01 AS country_id,
        mcs.total_amount,
        PERCENT_RANK() OVER (
            PARTITION BY mcs.payment_month, c.h02, cnt.c01 
            ORDER BY mcs.total_amount
        ) AS p95_rank
    FROM monthly_customer_stats mcs
    JOIN cus c ON c.h01 = mcs.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ci ON ci.d01 = a.e05
    JOIN cnt cnt ON cnt.c01 = ci.d03
),
p95_thresholds AS (
    SELECT payment_month, store_id, country_id, MAX(total_amount) as p95_val
    FROM store_country_stats
    WHERE p95_rank <= 0.95
    GROUP BY payment_month, store_id, country_id
)
SELECT
    ch.customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    a.e02 AS address,
    ci.d02 AS city,
    cnt.c02 AS country,
    c.h02 AS store_id,
    ch.payment_month,
    ROUND(ch.total_amount, 2) AS total_amount,
    ch.payment_count,
    ch.staff_count,
    ROUND(ch.late_return_share, 4) AS late_return_share,
    RANK() OVER (PARTITION BY c.h02, ch.payment_month ORDER BY ch.total_amount DESC) AS store_rank
FROM customer_history ch
JOIN cus c ON c.h01 = ch.customer_id
JOIN adr a ON a.e01 = c.h06
JOIN cty ci ON ci.d01 = a.e05
JOIN cnt cnt ON cnt.c01 = ci.d03
JOIN p95_thresholds p95 ON p95.payment_month = ch.payment_month 
    AND p95.store_id = c.h02 AND p95.country_id = cnt.c01
WHERE ch.prev_avg_amount IS NOT NULL 
  AND ch.total_amount >= 3 * ch.prev_avg_amount
  AND ch.total_amount > p95.p95_val
ORDER BY ch.payment_month, ch.total_amount DESC;