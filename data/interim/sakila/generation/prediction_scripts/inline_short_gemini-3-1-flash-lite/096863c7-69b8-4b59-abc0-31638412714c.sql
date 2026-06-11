WITH daily_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_day,
        SUM(p.p05) AS daily_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, DATE(p.p06)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS cty ON cty.d01 = a.e05
    JOIN cnt AS cnt ON cnt.c01 = cty.d03
),
daily_with_baseline AS (
    SELECT
        dcs.*,
        cg.customer_name,
        cg.country_id,
        cg.country_name,
        (
            SELECT AVG(prev.daily_amount)
            FROM daily_customer_stats AS prev
            WHERE prev.customer_id = dcs.customer_id
              AND prev.payment_day >= DATE(dcs.payment_day, '-30 days')
              AND prev.payment_day < dcs.payment_day
        ) AS avg_30d_personal,
        (
            SELECT AVG(all_c.daily_amount)
            FROM daily_customer_stats AS all_c
            JOIN customer_geo AS cg2 ON cg2.customer_id = all_c.customer_id
            WHERE cg2.country_id = cg.country_id
              AND all_c.payment_day = dcs.payment_day
        ) AS avg_daily_country
    FROM daily_customer_stats AS dcs
    JOIN customer_geo AS cg ON cg.customer_id = dcs.customer_id
),
suspicious_days AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY country_id ORDER BY daily_amount DESC) AS country_rank
    FROM daily_with_baseline
    WHERE avg_30d_personal > 0
      AND daily_amount > (3 * avg_30d_personal)
      AND daily_amount > avg_daily_country
      AND (staff_count > 1 OR store_count > 1)
)
SELECT
    customer_name,
    country_name,
    payment_day,
    ROUND(daily_amount, 2) AS daily_amount,
    ROUND(avg_30d_personal, 2) AS avg_30d_personal,
    ROUND(avg_daily_country, 2) AS avg_daily_country,
    payment_count,
    staff_count,
    store_count,
    country_rank
FROM suspicious_days
ORDER BY country_name, country_rank;