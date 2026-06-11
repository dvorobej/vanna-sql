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
        c.c01 AS country_id,
        c.c02 AS country_name,
        m.payment_month,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY m.monthly_amount) OVER (PARTITION BY c.c01, m.payment_month) AS p95_amount
    FROM monthly_customer_stats m
    JOIN cus cu ON cu.h01 = m.customer_id
    JOIN adr a ON a.e01 = cu.h06
    JOIN cty ct ON ct.d01 = a.e05
    JOIN cnt c ON c.c01 = ct.d03
),
suspicious_activity AS (
    SELECT
        mwh.*,
        cu.h03 || ' ' || cu.h04 AS customer_name,
        ct.d02 AS city_name,
        c.c02 AS country_name,
        c.c01 AS country_id,
        RANK() OVER (PARTITION BY c.c01, mwh.payment_month ORDER BY mwh.monthly_amount DESC) AS country_rank
    FROM monthly_with_history mwh
    JOIN cus cu ON cu.h01 = mwh.customer_id
    JOIN adr a ON a.e01 = cu.h06
    JOIN cty ct ON ct.d01 = a.e05
    JOIN cnt c ON c.c01 = ct.d03
    JOIN country_stats cs ON cs.country_id = c.c01 AND cs.payment_month = mwh.payment_month
    WHERE mwh.history_months_count = 2
      AND mwh.monthly_amount > (2.0 * mwh.prev_2m_avg_amount)
      AND mwh.monthly_amount > cs.p95_amount
)
SELECT
    payment_month,
    customer_name,
    country_name,
    city_name,
    ROUND(monthly_amount, 2) AS monthly_amount,
    payment_count,
    ROUND(prev_2m_avg_amount, 2) AS prev_2m_avg_amount,
    ROUND(off_home_store_share, 4) AS off_home_store_share,
    staff_count,
    country_rank
FROM suspicious_activity
ORDER BY payment_month DESC, country_name, country_rank;