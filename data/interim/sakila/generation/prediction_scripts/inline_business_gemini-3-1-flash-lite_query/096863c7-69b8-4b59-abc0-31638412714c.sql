WITH daily_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        SUM(p.p05) AS daily_sum,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay p
    JOIN stf s ON p.p03 = s.o01
    GROUP BY p.p02, DATE(p.p06)
),
customer_rolling_avg AS (
    SELECT
        dcs.*,
        (
            SELECT AVG(prev.daily_sum)
            FROM daily_customer_stats prev
            WHERE prev.customer_id = dcs.customer_id
              AND prev.payment_date >= DATE(dcs.payment_date, '-30 days')
              AND prev.payment_date < dcs.payment_date
        ) AS avg_prev_30
    FROM daily_customer_stats dcs
),
country_daily_avg AS (
    SELECT
        c.h01 AS customer_id,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        c.h03 || ' ' || c.h04 AS customer_name
    FROM cus c
    JOIN adr a ON c.h06 = a.e01
    JOIN cty ON a.e05 = cty.d01
    JOIN cnt ON cty.d03 = cnt.c01
),
country_avg_stats AS (
    SELECT
        cg.country_id,
        AVG(dcs.daily_sum) AS country_avg_daily
    FROM daily_customer_stats dcs
    JOIN country_geo cg ON dcs.customer_id = cg.customer_id
    GROUP BY cg.country_id
),
suspicious_events AS (
    SELECT
        cra.*,
        cg.customer_name,
        cg.country_name,
        cg.city_name,
        cas.country_avg_daily,
        (cra.daily_sum - cra.avg_prev_30) AS deviation_personal,
        (cra.daily_sum - cas.country_avg_daily) AS deviation_country
    FROM customer_rolling_avg cra
    JOIN country_geo cg ON cra.customer_id = cg.customer_id
    JOIN country_avg_stats cas ON cg.country_id = cas.country_id
    WHERE cra.avg_prev_30 > 0
      AND cra.daily_sum > (3 * cra.avg_prev_30)
      AND cra.daily_sum > cas.country_avg_daily
      AND (cra.staff_count > 1 OR cra.store_count > 1)
)
SELECT
    customer_name,
    country_name,
    city_name,
    payment_date,
    daily_sum,
    payment_count,
    ROUND(deviation_personal, 2) AS deviation_personal,
    ROUND(deviation_country, 2) AS deviation_country,
    staff_count,
    store_count,
    RANK() OVER (PARTITION BY country_name ORDER BY daily_sum DESC) AS country_rank
FROM suspicious_events
ORDER BY country_name, country_rank;