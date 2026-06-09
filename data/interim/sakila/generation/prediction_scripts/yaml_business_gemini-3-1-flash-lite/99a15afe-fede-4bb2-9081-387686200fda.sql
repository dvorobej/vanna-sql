WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS total_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        SUM(CASE WHEN r.q05 > date(r.q02, '+' || flm.i07 || ' days') THEN 1.0 ELSE 0.0 END) / COUNT(*) AS late_return_share
    FROM pay p
    JOIN ren r ON r.q01 = p.p04
    JOIN inv i ON i.n01 = r.q03
    JOIN flm ON flm.i01 = i.n02
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_history AS (
    SELECT
        mcs.*,
        AVG(mcs.total_amount) OVER (
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
        cnt.c01 AS country_id,
        mcs.total_amount
    FROM monthly_customer_stats mcs
    JOIN cus c ON c.h01 = mcs.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ci ON ci.d01 = a.e05
    JOIN cnt ON cnt.c01 = ci.d03
),
percentiles AS (
    SELECT
        payment_month,
        store_id,
        country_id,
        -- SQLite approximation for 95th percentile
        MAX(total_amount) FILTER (WHERE rn <= total_count * 0.95) AS p95_amount
    FROM (
        SELECT *,
               ROW_NUMBER() OVER (PARTITION BY payment_month, store_id, country_id ORDER BY total_amount) as rn,
               COUNT(*) OVER (PARTITION BY payment_month, store_id, country_id) as total_count
        FROM store_country_stats
    )
    GROUP BY payment_month, store_id, country_id
),
final_report AS (
    SELECT
        ch.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        a.e02 AS address,
        ci.d02 AS city,
        cnt.c02 AS country,
        c.h02 AS store_id,
        RANK() OVER (PARTITION BY c.h02, ch.payment_month ORDER BY ch.total_amount DESC) AS store_rank
    FROM customer_history ch
    JOIN cus c ON c.h01 = ch.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ci ON ci.d01 = a.e05
    JOIN cnt ON cnt.c01 = ci.d03
    JOIN percentiles p ON p.payment_month = ch.payment_month AND p.store_id = c.h02 AND p.country_id = cnt.c01
    WHERE ch.prev_avg_amount IS NOT NULL
      AND ch.total_amount >= 3 * ch.prev_avg_amount
      AND ch.total_amount > p.p95_amount
)
SELECT
    payment_month,
    customer_name,
    address,
    city,
    country,
    store_id,
    total_amount,
    payment_count,
    staff_count,
    ROUND(late_return_share, 4) AS late_return_share,
    store_rank
FROM final_report
ORDER BY payment_month, store_id, store_rank;