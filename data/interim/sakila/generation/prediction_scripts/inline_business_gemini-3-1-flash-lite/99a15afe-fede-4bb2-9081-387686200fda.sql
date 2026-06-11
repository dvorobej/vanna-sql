WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS total_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        SUM(CASE WHEN r.q05 > date(r.q02, '+' || f.i07 || ' days') THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS late_return_share
    FROM pay p
    JOIN ren r ON p.p04 = r.q01
    JOIN inv i ON r.q03 = i.n01
    JOIN flm f ON i.n02 = f.i01
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
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY mcs.total_amount) OVER (PARTITION BY mcs.payment_month, c.h02, cnt.c01) AS p95_amount
    FROM monthly_customer_stats mcs
    JOIN cus c ON mcs.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ci ON a.e05 = ci.d01
    JOIN cnt ON ci.d03 = cnt.c01
),
suspicious_episodes AS (
    SELECT
        ch.*,
        c.h02 AS store_id,
        cnt.c02 AS country,
        a.e04 AS city,
        RANK() OVER (PARTITION BY c.h02, ch.payment_month ORDER BY ch.total_amount DESC) AS store_rank
    FROM customer_history ch
    JOIN cus c ON ch.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ci ON a.e05 = ci.d01
    JOIN cnt ON ci.d03 = cnt.c01
    JOIN store_country_stats scs ON ch.payment_month = scs.payment_month AND c.h02 = scs.store_id AND cnt.c01 = scs.country_id
    WHERE ch.prev_avg_amount IS NOT NULL
      AND ch.total_amount >= 3 * ch.prev_avg_amount
      AND ch.total_amount > scs.p95_amount
)
SELECT
    se.customer_id,
    se.payment_month,
    se.country,
    se.city,
    se.store_id,
    ROUND(se.total_amount, 2) AS total_amount,
    se.payment_count,
    se.staff_count,
    ROUND(se.late_return_share, 4) AS late_return_share,
    se.store_rank
FROM suspicious_episodes se
ORDER BY se.payment_month, se.store_id, se.store_rank;