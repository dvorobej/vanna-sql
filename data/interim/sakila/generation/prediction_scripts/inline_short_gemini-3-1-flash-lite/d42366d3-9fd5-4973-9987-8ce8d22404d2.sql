WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        c.h02 AS home_store_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        SUM(CASE WHEN s.o07 <> c.h02 THEN 1.0 ELSE 0.0 END) / COUNT(*) AS off_home_store_share,
        ct.d03 AS country_id
    FROM pay p
    JOIN cus c ON p.p02 = c.h01
    JOIN stf s ON p.p03 = s.o01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ct ON a.e05 = ct.d01
    GROUP BY p.p02, c.h02, strftime('%Y-%m', p.p06), ct.d03
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
        SELECT *,
               ROW_NUMBER() OVER (PARTITION BY country_id, payment_month ORDER BY monthly_amount) AS rn,
               COUNT(*) OVER (PARTITION BY country_id, payment_month) AS total_count
        FROM monthly_customer_stats
    )
    GROUP BY country_id, payment_month
),
suspicious_activity AS (
    SELECT
        m.*,
        cp.p95_amount,
        RANK() OVER (PARTITION BY m.country_id, m.payment_month ORDER BY m.monthly_amount DESC) AS country_rank
    FROM monthly_with_history m
    JOIN country_percentiles cp ON m.country_id = cp.country_id AND m.payment_month = cp.payment_month
    WHERE m.monthly_amount > COALESCE(m.prev_2m_avg * 2, m.monthly_amount)
      AND m.monthly_amount > cp.p95_amount
)
SELECT
    s.customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    cnt.c02 AS country,
    s.payment_month,
    ROUND(s.monthly_amount, 2) AS monthly_amount,
    ROUND(s.prev_2m_avg, 2) AS prev_2m_avg,
    ROUND(s.p95_amount, 2) AS country_p95_amount,
    ROUND(s.off_home_store_share, 4) AS off_home_store_share,
    s.staff_count,
    s.country_rank
FROM suspicious_activity s
JOIN cus c ON s.customer_id = c.h01
JOIN cnt cnt ON s.country_id = cnt.c01
ORDER BY s.payment_month DESC, s.country_rank ASC;