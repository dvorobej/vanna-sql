WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        c.h02 AS home_store_id,
        co.c01 AS country_id,
        co.c02 AS country_name,
        strftime('%Y-%m', p.p06) AS payment_month,
        COUNT(*) AS monthly_payment_count,
        SUM(p.p05) AS monthly_payment_sum,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        SUM(CASE WHEN s.o07 <> c.h02 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS off_home_store_share
    FROM pay p
    JOIN cus c ON p.p02 = c.h01
    JOIN stf s ON p.p03 = s.o01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ci ON a.e05 = ci.d01
    JOIN cnt co ON ci.d03 = co.c01
    GROUP BY 1, 2, 3, 4, 5
),
moving_avg AS (
    SELECT
        *,
        AVG(monthly_payment_sum) OVER (
            PARTITION BY customer_id 
            ORDER BY payment_month 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS personal_avg_sum_2m
    FROM monthly_customer_stats
),
country_percentiles AS (
    SELECT
        country_id,
        payment_month,
        monthly_payment_sum,
        PERCENT_RANK() OVER (
            PARTITION BY country_id, payment_month 
            ORDER BY monthly_payment_sum
        ) AS p_rank
    FROM monthly_customer_stats
),
p95_thresholds AS (
    SELECT
        country_id,
        payment_month,
        MIN(monthly_payment_sum) AS p95_sum
    FROM country_percentiles
    WHERE p_rank >= 0.95
    GROUP BY 1, 2
),
suspicious_cases AS (
    SELECT
        ma.*,
        RANK() OVER (
            PARTITION BY ma.country_id, ma.payment_month 
            ORDER BY ma.monthly_payment_sum DESC
        ) AS country_rank
    FROM moving_avg ma
    JOIN p95_thresholds p95 
      ON ma.country_id = p95.country_id 
     AND ma.payment_month = p95.payment_month
    WHERE ma.personal_avg_sum_2m IS NOT NULL
      AND ma.monthly_payment_sum >= 3 * ma.personal_avg_sum_2m
      AND ma.monthly_payment_sum >= p95.p95_sum
)
SELECT
    payment_month,
    customer_id,
    country_name,
    monthly_payment_count,
    ROUND(monthly_payment_sum, 2) AS monthly_payment_sum,
    ROUND(personal_avg_sum_2m, 2) AS personal_avg_sum_2m,
    ROUND(off_home_store_share, 4) AS off_home_store_share,
    distinct_staff_count,
    country_rank
FROM suspicious_cases
ORDER BY payment_month, country_name, country_rank;