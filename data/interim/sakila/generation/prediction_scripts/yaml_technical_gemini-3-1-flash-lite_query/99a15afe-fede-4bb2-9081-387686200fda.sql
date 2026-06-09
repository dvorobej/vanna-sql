WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        AVG(CASE WHEN r.q05 > date(r.q02, '+' || flm.i07 || ' days') THEN 1.0 ELSE 0.0 END) AS late_return_share
    FROM pay p
    JOIN ren r ON p.p04 = r.q01
    JOIN inv i ON r.q03 = i.n01
    JOIN flm ON i.n02 = flm.i01
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_history AS (
    SELECT
        mcs.*,
        AVG(mcs.monthly_amount) OVER (
            PARTITION BY mcs.customer_id 
            ORDER BY mcs.payment_month 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_amount
    FROM monthly_customer_stats mcs
),
store_country_stats AS (
    SELECT
        mcs.payment_month,
        c.h02 AS store_id,
        co.c01 AS country_id,
        mcs.monthly_amount
    FROM monthly_customer_stats mcs
    JOIN cus c ON mcs.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ci ON a.e05 = ci.d01
    JOIN cnt co ON ci.d03 = co.c01
),
percentiles AS (
    SELECT
        payment_month,
        store_id,
        country_id,
        -- SQLite approximation for 95th percentile
        MAX(monthly_amount) FILTER (WHERE rn <= total * 0.95) AS p95_amount
    FROM (
        SELECT *,
               ROW_NUMBER() OVER (PARTITION BY payment_month, store_id, country_id ORDER BY monthly_amount) as rn,
               COUNT(*) OVER (PARTITION BY payment_month, store_id, country_id) as total
        FROM store_country_stats
    )
    GROUP BY payment_month, store_id, country_id
),
final_ranking AS (
    SELECT
        ch.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        co.c02 AS country,
        ci.d02 AS city,
        c.h02 AS store_id,
        RANK() OVER (PARTITION BY c.h02, ch.payment_month ORDER BY ch.monthly_amount DESC) AS store_rank
    FROM customer_history ch
    JOIN cus c ON ch.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ci ON a.e05 = ci.d01
    JOIN cnt co ON ci.d03 = co.c01
    JOIN percentiles p ON ch.payment_month = p.payment_month 
                       AND c.h02 = p.store_id 
                       AND co.c01 = p.country_id
    WHERE ch.prev_avg_amount IS NOT NULL
      AND ch.monthly_amount >= 3 * ch.prev_avg_amount
      AND ch.monthly_amount > p.p95_amount
)
SELECT
    customer_name,
    country,
    city,
    store_id,
    payment_month,
    monthly_amount,
    payment_count,
    staff_count,
    late_return_share,
    store_rank
FROM final_ranking
ORDER BY payment_month, store_id, store_rank;