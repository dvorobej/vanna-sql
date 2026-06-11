WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay p
    JOIN stf s ON p.p03 = s.o01
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_history AS (
    SELECT
        ms.*,
        AVG(ms.monthly_sum) OVER (
            PARTITION BY ms.customer_id 
            ORDER BY ms.payment_month 
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS avg_prev_3_months
    FROM monthly_stats ms
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
country_median AS (
    SELECT
        cs.country_id,
        ch.payment_month,
        AVG(ch.monthly_sum) AS median_country_sum
    FROM customer_history ch
    JOIN country_stats cs ON ch.customer_id = cs.customer_id
    GROUP BY cs.country_id, ch.payment_month
),
ranked_data AS (
    SELECT
        ch.*,
        cs.country_name,
        cs.city_name,
        cm.median_country_sum,
        RANK() OVER (
            PARTITION BY cs.country_id, ch.payment_month 
            ORDER BY ch.monthly_sum DESC
        ) AS country_rank,
        COUNT(*) OVER (
            PARTITION BY cs.country_id, ch.payment_month
        ) AS country_total_customers
    FROM customer_history ch
    JOIN country_stats cs ON ch.customer_id = cs.customer_id
    JOIN country_median cm ON cs.country_id = cm.country_id AND ch.payment_month = cm.payment_month
)
SELECT
    payment_month,
    customer_id,
    country_name,
    city_name,
    monthly_sum,
    payment_count,
    staff_count,
    store_count,
    country_rank
FROM ranked_data
WHERE monthly_sum > 3.0 * COALESCE(avg_prev_3_months, 0)
  AND monthly_sum > 2.0 * median_country_sum
  AND country_rank <= (country_total_customers * 0.05)
ORDER BY payment_month DESC, country_name, country_rank;