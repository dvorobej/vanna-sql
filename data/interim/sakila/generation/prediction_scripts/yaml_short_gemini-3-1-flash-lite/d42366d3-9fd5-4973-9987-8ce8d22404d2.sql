WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        c.h02 AS home_store_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        SUM(CASE WHEN s.o07 <> c.h02 THEN 1.0 ELSE 0.0 END) / COUNT(*) AS off_home_store_share
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, c.h02, strftime('%Y-%m', p.p06)
),
monthly_with_history AS (
    SELECT
        mcs.*,
        AVG(mcs.monthly_amount) OVER (
            PARTITION BY mcs.customer_id 
            ORDER BY mcs.payment_month 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS prev_2m_avg_amount,
        COUNT(mcs.monthly_amount) OVER (
            PARTITION BY mcs.customer_id 
            ORDER BY mcs.payment_month 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS history_months_count
    FROM monthly_customer_stats mcs
),
country_stats AS (
    SELECT
        c.h01 AS customer_id,
        co.c01 AS country_id,
        co.c02 AS country_name,
        ci.d02 AS city_name
    FROM cus c
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ci ON ci.d01 = a.e05
    JOIN cnt co ON co.c01 = ci.d03
),
country_percentiles AS (
    SELECT
        cs.country_id,
        MAX(CASE WHEN rn <= (cnt * 0.95) THEN monthly_amount END) AS p95_monthly_amount
    FROM (
        SELECT 
            cs.country_id, 
            mws.monthly_amount,
            ROW_NUMBER() OVER (PARTITION BY cs.country_id ORDER BY mws.monthly_amount) AS rn,
            COUNT(*) OVER (PARTITION BY cs.country_id) AS cnt
        FROM monthly_with_history mws
        JOIN country_stats cs ON cs.customer_id = mws.customer_id
    ) t
    GROUP BY country_id
),
suspicious_activity AS (
    SELECT
        mws.*,
        cs.country_name,
        cs.city_name,
        cp.p95_monthly_amount,
        RANK() OVER (PARTITION BY cs.country_id, mws.payment_month ORDER BY mws.monthly_amount DESC) AS country_rank
    FROM monthly_with_history mws
    JOIN country_stats cs ON cs.customer_id = mws.customer_id
    JOIN country_percentiles cp ON cp.country_id = cs.country_id
    WHERE mws.history_months_count = 2
      AND mws.monthly_amount > (2.0 * mws.prev_2m_avg_amount)
      AND mws.monthly_amount > cp.p95_monthly_amount
)
SELECT
    customer_id,
    country_name,
    city_name,
    payment_month,
    ROUND(monthly_amount, 2) AS monthly_amount,
    payment_count,
    ROUND(prev_2m_avg_amount, 2) AS prev_2m_avg_amount,
    ROUND(off_home_store_share, 4) AS off_home_store_share,
    staff_count,
    country_rank
FROM suspicious_activity
ORDER BY payment_month DESC, country_name, country_rank;