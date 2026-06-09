WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(*) AS monthly_count,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        SUM(CASE WHEN s.o07 <> c.h02 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS off_home_store_share
    FROM pay p
    JOIN cus c ON c.h01 = p.p02
    JOIN stf s ON s.o01 = p.p03
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_history AS (
    SELECT
        mcs.*,
        c.h02 AS home_store_id,
        co.c01 AS country_id,
        AVG(mcs.monthly_sum) OVER (
            PARTITION BY mcs.customer_id 
            ORDER BY mcs.payment_month 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS personal_avg_sum_2m,
        COUNT(mcs.monthly_sum) OVER (
            PARTITION BY mcs.customer_id 
            ORDER BY mcs.payment_month 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS history_months_count
    FROM monthly_customer_stats mcs
    JOIN cus c ON c.h01 = mcs.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ci ON ci.d01 = a.e05
    JOIN cnt co ON co.c01 = ci.d03
),
country_percentiles AS (
    SELECT
        country_id,
        payment_month,
        monthly_sum,
        PERCENT_RANK() OVER (PARTITION BY country_id, payment_month ORDER BY monthly_sum) AS p_rank
    FROM (
        SELECT co.c01 AS country_id, strftime('%Y-%m', p.p06) AS payment_month, SUM(p.p05) AS monthly_sum
        FROM pay p
        JOIN cus c ON c.h01 = p.p02
        JOIN adr a ON a.e01 = c.h06
        JOIN cty ci ON ci.d01 = a.e05
        JOIN cnt co ON co.c01 = ci.d03
        GROUP BY co.c01, strftime('%Y-%m', p.p06), p.p02
    )
),
p95_thresholds AS (
    SELECT country_id, payment_month, MIN(monthly_sum) AS p95_sum
    FROM country_percentiles
    WHERE p_rank >= 0.95
    GROUP BY country_id, payment_month
)
SELECT
    ch.payment_month,
    ch.customer_id,
    ch.monthly_sum,
    ch.monthly_count,
    ch.personal_avg_sum_2m,
    ch.off_home_store_share,
    ch.distinct_staff_count,
    RANK() OVER (PARTITION BY ch.country_id, ch.payment_month ORDER BY ch.monthly_sum DESC) AS country_rank
FROM customer_history ch
JOIN p95_thresholds p95 ON p95.country_id = ch.country_id AND p95.payment_month = ch.payment_month
WHERE ch.history_months_count = 2
  AND ch.monthly_sum >= 3 * ch.personal_avg_sum_2m
  AND ch.monthly_sum >= p95.p95_sum
ORDER BY ch.payment_month, ch.country_id, country_rank;