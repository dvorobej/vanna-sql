WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        c.h02 AS home_store_id,
        ci.d03 AS country_id,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS payment_sum,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        SUM(CASE WHEN s.o07 <> c.h02 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS off_home_store_share
    FROM pay p
    JOIN cus c ON p.p02 = c.h01
    JOIN stf s ON p.p03 = s.o01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ci ON a.e05 = ci.d01
    GROUP BY p.p02, strftime('%Y-%m', p.p06), c.h02, ci.d03
),
monthly_history AS (
    SELECT
        *,
        AVG(payment_sum) OVER (
            PARTITION BY customer_id 
            ORDER BY payment_month 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS personal_avg_sum_2m,
        COUNT(payment_sum) OVER (
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
        MAX(CASE WHEN rn <= cnt * 0.95 THEN payment_sum END) AS p95_sum
    FROM (
        SELECT 
            country_id, payment_month, payment_sum,
            ROW_NUMBER() OVER (PARTITION BY country_id, payment_month ORDER BY payment_sum) AS rn,
            COUNT(*) OVER (PARTITION BY country_id, payment_month) AS cnt
        FROM monthly_customer_stats
    )
    GROUP BY country_id, payment_month
),
suspicious_cases AS (
    SELECT
        m.*,
        cp.p95_sum,
        RANK() OVER (PARTITION BY m.country_id, m.payment_month ORDER BY m.payment_sum DESC) AS country_rank
    FROM monthly_history m
    JOIN country_percentiles cp ON m.country_id = cp.country_id AND m.payment_month = cp.payment_month
    WHERE m.history_months_count = 2
      AND m.payment_sum > 3 * m.personal_avg_sum_2m
      AND m.payment_sum > cp.p95_sum
)
SELECT
    s.payment_month,
    s.customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country,
    s.payment_count,
    ROUND(s.payment_sum, 2) AS payment_sum,
    ROUND(s.personal_avg_sum_2m, 2) AS personal_avg_sum_2m,
    ROUND(s.off_home_store_share, 4) AS off_home_store_share,
    s.distinct_staff_count,
    s.country_rank
FROM suspicious_cases s
JOIN cus c ON s.customer_id = c.h01
JOIN cnt ON s.country_id = cnt.c01
ORDER BY s.payment_month DESC, s.country_rank ASC;