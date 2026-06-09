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
        c.h02 AS home_store_id,
        cty.d03 AS country_id,
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
    JOIN cus c ON mcs.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ON a.e05 = cty.d01
),
country_percentiles AS (
    SELECT
        country_id,
        payment_month,
        MAX(CASE WHEN rn <= total_count * 0.95 THEN payment_sum END) AS p95_sum
    FROM (
        SELECT
            cty.d03 AS country_id,
            strftime('%Y-%m', p.p06) AS payment_month,
            SUM(p.p05) AS payment_sum,
            ROW_NUMBER() OVER (PARTITION BY cty.d03, strftime('%Y-%m', p.p06) ORDER BY SUM(p.p05)) AS rn,
            COUNT(*) OVER (PARTITION BY cty.d03, strftime('%Y-%m', p.p06)) AS total_count
        FROM pay p
        JOIN cus c ON p.p02 = c.h01
        JOIN adr a ON c.h06 = a.e01
        JOIN cty ON a.e05 = cty.d01
        GROUP BY cty.d03, strftime('%Y-%m', p.p06), p.p02
    ) t
    GROUP BY country_id, payment_month
)
SELECT
    ch.customer_id,
    ch.payment_month,
    ch.payment_count,
    ch.payment_sum,
    ch.off_home_store_share,
    ch.distinct_staff_count,
    RANK() OVER (PARTITION BY ch.country_id, ch.payment_month ORDER BY ch.payment_sum DESC) AS country_rank
FROM customer_history ch
JOIN country_percentiles cp ON ch.country_id = cp.country_id AND ch.payment_month = cp.payment_month
WHERE ch.history_months_count = 2
  AND ch.payment_sum > 3 * ch.personal_avg_sum_2m
  AND ch.payment_sum > cp.p95_sum;