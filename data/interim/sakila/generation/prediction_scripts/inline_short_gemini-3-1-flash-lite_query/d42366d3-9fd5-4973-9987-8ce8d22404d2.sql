WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        COUNT(*) AS monthly_payment_count,
        SUM(p.p05) AS monthly_payment_sum,
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
        AVG(mcs.monthly_payment_sum) OVER (
            PARTITION BY mcs.customer_id 
            ORDER BY mcs.payment_month 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS personal_avg_sum_2m,
        COUNT(mcs.monthly_payment_sum) OVER (
            PARTITION BY mcs.customer_id 
            ORDER BY mcs.payment_month 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS history_months_count
    FROM monthly_customer_stats mcs
),
country_stats AS (
    SELECT
        c.h01 AS customer_id,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        cty.d02 AS city_name
    FROM cus c
    JOIN adr a ON a.e01 = c.h06
    JOIN cty cty ON cty.d01 = a.e05
    JOIN cnt cnt ON cnt.c01 = cty.d03
),
country_percentiles AS (
    SELECT
        mcs.payment_month,
        cs.country_id,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY mcs.monthly_payment_sum) OVER (
            PARTITION BY cs.country_id, mcs.payment_month
        ) AS p95_country_sum
    FROM monthly_customer_stats mcs
    JOIN country_stats cs ON cs.customer_id = mcs.customer_id
),
suspicious_cases AS (
    SELECT
        ch.*,
        cs.country_name,
        cs.city_name,
        cp.p95_country_sum,
        RANK() OVER (
            PARTITION BY cs.country_id, ch.payment_month 
            ORDER BY ch.monthly_payment_sum DESC
        ) AS country_rank
    FROM customer_history ch
    JOIN country_stats cs ON cs.customer_id = ch.customer_id
    JOIN country_percentiles cp ON cp.country_id = cs.country_id AND cp.payment_month = ch.payment_month
    WHERE ch.history_months_count = 2
      AND ch.monthly_payment_sum > 3 * ch.personal_avg_sum_2m
      AND ch.monthly_payment_sum > cp.p95_country_sum
)
SELECT
    payment_month,
    customer_id,
    country_name,
    city_name,
    monthly_payment_sum,
    monthly_payment_count,
    personal_avg_sum_2m,
    off_home_store_share,
    distinct_staff_count,
    country_rank
FROM suspicious_cases
ORDER BY payment_month, country_name, country_rank;