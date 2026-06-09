WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        c.h02 AS home_store_id,
        co.c01 AS country_id,
        co.c02 AS country_name,
        ci.d02 AS city_name,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        SUM(CASE WHEN s.o07 <> c.h02 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS off_home_store_share
    FROM pay p
    JOIN cus c ON p.p02 = c.h01
    JOIN stf s ON p.p03 = s.o01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ci ON a.e05 = ci.d01
    JOIN cnt co ON ci.d03 = co.c01
    GROUP BY 1, 2, 3, 4, 5, 6
),
monthly_with_history AS (
    SELECT
        *,
        AVG(monthly_amount) OVER (
            PARTITION BY customer_id 
            ORDER BY payment_month 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS prev_2m_avg
    FROM monthly_customer_stats
),
country_percentiles AS (
    SELECT
        country_id,
        payment_month,
        -- SQLite не поддерживает PERCENTILE_CONT, используем метод ранжирования для 95-го перцентиля
        MAX(CASE WHEN rn >= total_count * 0.95 THEN monthly_amount END) AS p95_amount
    FROM (
        SELECT 
            country_id, payment_month, monthly_amount,
            ROW_NUMBER() OVER (PARTITION BY country_id, payment_month ORDER BY monthly_amount) AS rn,
            COUNT(*) OVER (PARTITION BY country_id, payment_month) AS total_count
        FROM monthly_customer_stats
    )
    GROUP BY 1, 2
),
suspicious_activity AS (
    SELECT
        m.*,
        cp.p95_amount,
        RANK() OVER (PARTITION BY m.country_id, m.payment_month ORDER BY m.monthly_amount DESC) AS country_rank
    FROM monthly_with_history m
    JOIN country_percentiles cp ON m.country_id = cp.country_id AND m.payment_month = cp.payment_month
    WHERE m.prev_2m_avg IS NOT NULL
      AND m.monthly_amount > (m.prev_2m_avg * 2)
      AND m.monthly_amount > cp.p95_amount
)
SELECT
    customer_id,
    country_name,
    city_name,
    payment_month,
    ROUND(monthly_amount, 2) AS monthly_amount,
    payment_count,
    staff_count,
    ROUND(off_home_store_share, 4) AS off_home_store_share,
    ROUND(prev_2m_avg, 2) AS prev_2m_avg,
    ROUND(p95_amount, 2) AS country_p95_amount,
    country_rank
FROM suspicious_activity
ORDER BY payment_month DESC, country_rank ASC;