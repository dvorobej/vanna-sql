WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        c.h02 AS home_store_id,
        ci.d03 AS country_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        COUNT(*) AS monthly_payment_count,
        SUM(p.p05) AS monthly_payment_sum,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        SUM(CASE WHEN s.o07 <> c.h02 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS off_home_store_share
    FROM pay p
    JOIN cus c ON p.p02 = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ci ON a.e05 = ci.d01
    JOIN stf s ON p.p03 = s.o01
    GROUP BY 1, 2, 3, 4
),
monthly_history AS (
    SELECT
        *,
        AVG(monthly_payment_sum) OVER (
            PARTITION BY customer_id 
            ORDER BY payment_month 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS personal_avg_sum_2m,
        COUNT(monthly_payment_sum) OVER (
            PARTITION BY customer_id 
            ORDER BY payment_month 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS history_months_count
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
ranked_clients AS (
    SELECT
        *,
        RANK() OVER (
            PARTITION BY country_id, payment_month 
            ORDER BY monthly_payment_sum DESC
        ) AS country_rank
    FROM monthly_customer_stats
)
SELECT
    m.payment_month,
    m.customer_id,
    m.monthly_payment_sum,
    m.monthly_payment_count,
    m.personal_avg_sum_2m,
    m.off_home_store_share,
    m.distinct_staff_count,
    r.country_rank
FROM monthly_history m
JOIN p95_thresholds p ON m.country_id = p.country_id AND m.payment_month = p.payment_month
JOIN ranked_clients r ON m.customer_id = r.customer_id AND m.payment_month = r.payment_month
WHERE m.history_months_count = 2
  AND m.monthly_payment_sum >= 3 * m.personal_avg_sum_2m
  AND m.monthly_payment_sum >= p.p95_sum
ORDER BY m.payment_month DESC, m.monthly_payment_sum DESC;