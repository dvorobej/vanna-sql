WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        SUM(CASE WHEN r.q05 > date(r.q02, '+' || f.i07 || ' days') THEN 1.0 ELSE 0.0 END) / COUNT(*) AS late_return_share
    FROM pay p
    JOIN ren r ON p.p04 = r.q01
    JOIN inv i ON r.q03 = i.n01
    JOIN flm f ON i.n02 = f.i01
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_history AS (
    SELECT
        mcs.*,
        AVG(mcs.monthly_amount) OVER (
            PARTITION BY mcs.customer_id 
            ORDER BY mcs.payment_month 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount,
        c.h02 AS store_id,
        co.c02 AS country,
        ci.d02 AS city
    FROM monthly_customer_stats mcs
    JOIN cus c ON mcs.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ci ON a.e05 = ci.d01
    JOIN cnt co ON ci.d03 = co.c01
),
store_country_percentiles AS (
    SELECT
        store_id,
        country,
        payment_month,
        monthly_amount,
        PERCENT_RANK() OVER (
            PARTITION BY store_id, country, payment_month 
            ORDER BY monthly_amount
        ) AS p_rank
    FROM customer_history
),
ranked_customers AS (
    SELECT
        ch.*,
        RANK() OVER (
            PARTITION BY ch.store_id, ch.payment_month 
            ORDER BY ch.monthly_amount DESC
        ) AS store_rank
    FROM customer_history ch
    JOIN store_country_percentiles scp 
      ON ch.customer_id = (SELECT p02 FROM pay WHERE p01 = (SELECT p01 FROM pay WHERE p02 = ch.customer_id LIMIT 1)) -- Simplified join logic
      AND ch.payment_month = scp.payment_month
      AND ch.store_id = scp.store_id
      AND ch.country = scp.country
    WHERE ch.prev_avg_amount IS NOT NULL
      AND ch.monthly_amount >= 3 * ch.prev_avg_amount
      AND scp.p_rank >= 0.95
)
SELECT
    ch.customer_id,
    ch.country,
    ch.city,
    ch.store_id,
    ch.payment_month,
    ROUND(ch.monthly_amount, 2) AS monthly_amount,
    ch.payment_count,
    ch.staff_count,
    ROUND(ch.late_return_share, 4) AS late_return_share,
    rc.store_rank
FROM customer_history ch
JOIN ranked_customers rc ON ch.customer_id = rc.customer_id AND ch.payment_month = rc.payment_month
ORDER BY ch.payment_month, ch.store_id, rc.store_rank;