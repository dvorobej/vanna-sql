WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        COUNT(*) AS monthly_payment_count,
        SUM(p.p05) AS monthly_payment_sum,
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
        c.h02 AS home_store_id,
        cty.d03 AS country_id,
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
    JOIN cus c ON mcs.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ON a.e05 = cty.d01
),
country_percentiles AS (
    SELECT
        country_id,
        payment_month,
        monthly_payment_sum,
        PERCENT_RANK() OVER (PARTITION BY country_id, payment_month ORDER BY monthly_payment_sum) as p_rank
    FROM (
        SELECT cty.d03 AS country_id, strftime('%Y-%m', p.p06) AS payment_month, SUM(p.p05) AS monthly_payment_sum
        FROM pay p
        JOIN cus c ON p.p02 = c.h01
        JOIN adr a ON c.h06 = a.e01
        JOIN cty ON a.e05 = cty.d01
        GROUP BY cty.d03, strftime('%Y-%m', p.p06), p.p02
    )
),
p95_thresholds AS (
    SELECT country_id, payment_month, MIN(monthly_payment_sum) as p95_sum
    FROM country_percentiles
    WHERE p_rank >= 0.95
    GROUP BY country_id, payment_month
),
suspicious_cases AS (
    SELECT
        ch.*,
        p95.p95_sum,
        RANK() OVER (PARTITION BY ch.country_id, ch.payment_month ORDER BY ch.monthly_payment_sum DESC) as country_rank
    FROM customer_history ch
    JOIN p95_thresholds p95 ON ch.country_id = p95.country_id AND ch.payment_month = p95.payment_month
    WHERE ch.history_months_count = 2
      AND ch.monthly_payment_sum >= 3 * ch.personal_avg_sum_2m
      AND ch.monthly_payment_sum >= p95.p95_sum
)
SELECT
    sc.payment_month,
    sc.customer_id,
    sc.monthly_payment_count,
    sc.monthly_payment_sum,
    sc.personal_avg_sum_2m,
    sc.off_home_store_share,
    sc.distinct_staff_count,
    sc.country_rank
FROM suspicious_cases sc
ORDER BY sc.payment_month DESC, sc.country_rank ASC;