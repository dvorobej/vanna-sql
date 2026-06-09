WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month,
        COUNT(p.p01) AS payment_count,
        SUM(p.p05) AS total_amount,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        COUNT(DISTINCT DATE(p.p06)) AS distinct_days
    FROM pay p
    JOIN stf s ON p.p03 = s.o01
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
monthly_with_history AS (
    SELECT
        ms.*,
        AVG(ms.total_amount) OVER (
            PARTITION BY ms.customer_id 
            ORDER BY ms.month 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS avg_prev_months
    FROM monthly_stats ms
),
suspicious_months AS (
    SELECT
        mwh.*,
        c.h03 AS first_name,
        c.h04 AS last_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        cnt.c01 AS country_id
    FROM monthly_with_history mwh
    JOIN cus c ON mwh.customer_id = c.h01
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ON a.e05 = cty.d01
    JOIN cnt ON cty.d03 = cnt.c01
    WHERE mwh.avg_prev_months IS NOT NULL
      AND mwh.total_amount >= 3 * mwh.avg_prev_months
      AND mwh.payment_count >= 3
      AND mwh.distinct_days >= 3
      AND (mwh.staff_count > 1 OR mwh.store_count > 1)
)
SELECT
    month,
    first_name,
    last_name,
    country,
    city,
    payment_count,
    total_amount,
    max_payment,
    ROUND(max_payment / total_amount, 4) AS max_payment_share,
    staff_count,
    store_count,
    RANK() OVER (PARTITION BY month, country_id ORDER BY total_amount DESC) AS country_rank
FROM suspicious_months
ORDER BY month DESC, country, country_rank;