WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS payment_sum,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        SUM(CASE WHEN s.o07 <> c.h02 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS off_home_store_share
    FROM pay p
    JOIN cus c ON p.p02 = c.h01
    JOIN stf s ON p.p03 = s.o01
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_history AS (
    SELECT
        mcs.*,
        AVG(mcs.payment_sum) OVER (
            PARTITION BY mcs.customer_id 
            ORDER BY mcs.payment_month 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS personal_avg_sum_2m,
        COUNT(mcs.payment_sum) OVER (
            PARTITION BY mcs.customer_id 
            ORDER BY mcs.payment_month 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS history_months_count
    FROM monthly_customer_stats mcs
),
country_stats AS (
    SELECT
        c.h01 AS customer_id,
        co.c01 AS country_id,
        co.c02 AS country_name,
        ci.d02 AS city_name
    FROM cus c
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ci ON a.e05 = ci.d01
    JOIN cnt co ON ci.d03 = co.c01
),
country_percentiles AS (
    SELECT
        country_id,
        payment_month,
        MAX(CASE WHEN rn <= cnt * 0.95 THEN payment_sum END) AS p95_sum
    FROM (
        SELECT
            cs.country_id,
            mcs.payment_month,
            mcs.payment_sum,
            ROW_NUMBER() OVER (PARTITION BY cs.country_id, mcs.payment_month ORDER BY mcs.payment_sum) AS rn,
            COUNT(*) OVER (PARTITION BY cs.country_id, mcs.payment_month) AS cnt
        FROM monthly_customer_stats mcs
        JOIN country_stats cs ON mcs.customer_id = cs.customer_id
    ) t
    GROUP BY country_id, payment_month
),
ranked_clients AS (
    SELECT
        ch.*,
        cs.country_name,
        cs.city_name,
        RANK() OVER (
            PARTITION BY cs.country_id, ch.payment_month 
            ORDER BY ch.payment_sum DESC
        ) AS country_rank
    FROM customer_history ch
    JOIN country_stats cs ON ch.customer_id = cs.customer_id
    JOIN country_percentiles cp ON cs.country_id = cp.country_id AND ch.payment_month = cp.payment_month
    WHERE ch.history_months_count = 2
      AND ch.payment_sum >= 3 * ch.personal_avg_sum_2m
      AND ch.payment_sum > cp.p95_sum
)
SELECT
    payment_month,
    customer_id,
    country_name,
    city_name,
    payment_count,
    ROUND(payment_sum, 2) AS payment_sum,
    ROUND(personal_avg_sum_2m, 2) AS personal_avg_sum_2m,
    ROUND(off_home_store_share, 4) AS off_home_store_share,
    distinct_staff_count,
    country_rank
FROM ranked_clients
ORDER BY payment_month DESC, country_name, country_rank;