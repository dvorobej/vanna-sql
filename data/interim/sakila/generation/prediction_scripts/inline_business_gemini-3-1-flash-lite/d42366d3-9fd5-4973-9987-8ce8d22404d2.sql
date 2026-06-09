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
        AVG(mcs.monthly_sum) OVER (
            PARTITION BY mcs.customer_id 
            ORDER BY mcs.payment_month 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS avg_prev_2_months_sum,
        c.h03, c.h04, c.h02 AS home_store_id,
        co.c01 AS country_id, co.c02 AS country_name,
        ci.d02 AS city_name
    FROM monthly_customer_stats mcs
    JOIN cus c ON c.h01 = mcs.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ci ON ci.d01 = a.e05
    JOIN cnt co ON co.c01 = ci.d03
),
country_stats AS (
    SELECT
        country_id,
        payment_month,
        AVG(monthly_sum) AS avg_country_sum,
        STDEV(monthly_sum) AS stddev_country_sum
    FROM monthly_customer_stats mcs
    JOIN cus c ON c.h01 = mcs.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ci ON ci.d01 = a.e05
    GROUP BY country_id, payment_month
),
suspicious_activity AS (
    SELECT
        ch.*,
        cs.avg_country_sum,
        RANK() OVER (PARTITION BY ch.country_id, ch.payment_month ORDER BY ch.monthly_sum DESC) AS country_rank
    FROM customer_history ch
    JOIN country_stats cs ON cs.country_id = ch.country_id AND cs.payment_month = ch.payment_month
    WHERE ch.avg_prev_2_months_sum IS NOT NULL
      AND ch.monthly_sum > 2.0 * ch.avg_prev_2_months_sum
      AND ch.monthly_sum > cs.avg_country_sum + cs.stddev_country_sum
)
SELECT
    payment_month,
    h03 || ' ' || h04 AS customer_name,
    country_name,
    city_name,
    monthly_sum,
    monthly_count,
    avg_prev_2_months_sum,
    avg_country_sum,
    distinct_staff_count,
    off_home_store_share,
    country_rank
FROM suspicious_activity
ORDER BY payment_month DESC, country_name, country_rank;