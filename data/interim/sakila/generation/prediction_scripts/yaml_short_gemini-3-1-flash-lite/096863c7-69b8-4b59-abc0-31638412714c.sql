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
daily_with_history AS (
    SELECT
        dcs.*,
        (
            SELECT AVG(h.daily_amount)
            FROM daily_customer_stats AS h
            WHERE h.customer_id = dcs.customer_id
              AND h.payment_day >= DATE(dcs.payment_day, '-30 days')
              AND h.payment_day < dcs.payment_day
        ) AS avg_30d_personal
    FROM daily_customer_stats AS dcs
),
country_daily_avg AS (
    SELECT
        cg.country_id,
        AVG(dcs.daily_amount) AS avg_daily_country
    FROM daily_customer_stats AS dcs
    JOIN customer_geo AS cg ON cg.customer_id = dcs.customer_id
    GROUP BY cg.country_id
),
suspicious_activity AS (
    SELECT
        dwh.*,
        cg.customer_name,
        cg.country_name,
        cda.avg_daily_country
    FROM daily_with_history AS dwh
    JOIN customer_geo AS cg ON cg.customer_id = dwh.customer_id
    JOIN country_daily_avg AS cda ON cda.country_id = cg.country_id
    WHERE dwh.avg_30d_personal > 0
      AND dwh.daily_amount > (3 * dwh.avg_30d_personal)
      AND dwh.daily_amount > cda.avg_daily_country
      AND (dwh.staff_count > 1 OR dwh.store_count > 1)
)
SELECT
    customer_name,
    country_name,
    payment_day,
    daily_amount,
    ROUND(avg_30d_personal, 2) AS avg_30d_personal,
    ROUND(avg_daily_country, 2) AS avg_daily_country,
    payment_count,
    staff_count,
    store_count,
    RANK() OVER (
        PARTITION BY country_name
        ORDER BY daily_amount DESC
    ) AS country_rank
FROM suspicious_activity
ORDER BY country_name, country_rank;