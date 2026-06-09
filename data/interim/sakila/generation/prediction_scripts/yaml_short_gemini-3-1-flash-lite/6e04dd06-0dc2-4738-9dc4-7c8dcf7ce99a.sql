WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT i.n03) AS store_count,
        c.h02 AS home_store_id,
        co.c01 AS country_id,
        co.c02 AS country_name
    FROM pay p
    JOIN cus c ON p.p02 = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ci ON a.e05 = ci.d01
    JOIN cnt co ON ci.d03 = co.c01
    LEFT JOIN ren r ON p.p04 = r.q01
    LEFT JOIN inv i ON r.q03 = i.n01
    GROUP BY 1, 2, 7, 8, 9
),
history_and_median AS (
    SELECT
        ms.*,
        AVG(ms.monthly_amount) OVER (
            PARTITION BY ms.customer_id 
            ORDER BY ms.payment_month 
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prev_3m_avg,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ms.monthly_amount) OVER (
            PARTITION BY ms.country_id, ms.payment_month
        ) AS country_median_amount,
        PERCENT_RANK() OVER (
            PARTITION BY ms.country_id, ms.payment_month 
            ORDER BY ms.monthly_amount DESC
        ) AS country_percentile
    FROM monthly_stats ms
),
suspicious_cases AS (
    SELECT *
    FROM history_and_median
    WHERE prev_3m_avg > 0
      AND monthly_amount > (3.0 * prev_3m_avg)
      AND monthly_amount > (2.0 * country_median_amount)
      AND country_percentile <= 0.05
)
SELECT
    sc.customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    sc.country_name,
    sc.payment_month,
    ROUND(sc.monthly_amount, 2) AS monthly_amount,
    sc.payment_count,
    sc.staff_count,
    sc.store_count,
    ROUND(sc.prev_3m_avg, 2) AS prev_3m_avg,
    ROUND(sc.country_median_amount, 2) AS country_median_amount,
    ROUND(sc.country_percentile, 4) AS country_percentile
FROM suspicious_cases sc
JOIN cus c ON sc.customer_id = c.h01
ORDER BY sc.payment_month DESC, sc.country_name, sc.monthly_amount DESC;