WITH daily_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        SUM(p.p05) AS daily_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, DATE(p.p06)
),
customer_rolling_avg AS (
    SELECT
        dcs.*,
        (
            SELECT AVG(prev.daily_amount)
            FROM daily_customer_stats AS prev
            WHERE prev.customer_id = dcs.customer_id
              AND prev.payment_date >= DATE(dcs.payment_date, '-30 days')
              AND prev.payment_date < dcs.payment_date
        ) AS avg_30d
    FROM daily_customer_stats AS dcs
),
country_daily_avg AS (
    SELECT
        c.c01 AS country_id,
        dcs.payment_date,
        AVG(dcs.daily_amount) AS country_avg_daily
    FROM daily_customer_stats AS dcs
    JOIN cus AS cu ON cu.h01 = dcs.customer_id
    JOIN adr AS a ON a.e01 = cu.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS c ON c.c01 = ct.d03
    GROUP BY c.c01, dcs.payment_date
),
suspicious_events AS (
    SELECT
        cra.*,
        cu.h03 || ' ' || cu.h04 AS customer_name,
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        cda.country_avg_daily,
        cra.daily_amount - cra.avg_30d AS deviation_personal,
        cra.daily_amount - cda.country_avg_daily AS deviation_country
    FROM customer_rolling_avg AS cra
    JOIN cus AS cu ON cu.h01 = cra.customer_id
    JOIN adr AS a ON a.e01 = cu.h06
    JOIN cty AS cty ON cty.d01 = a.e05
    JOIN cnt AS cnt ON cnt.c01 = cty.d03
    JOIN country_daily_avg AS cda ON cda.country_id = cnt.c01 AND cda.payment_date = cra.payment_date
    WHERE cra.avg_30d > 0
      AND cra.daily_amount > 3 * cra.avg_30d
      AND cra.daily_amount > cda.country_avg_daily
      AND (cra.staff_count > 1 OR cra.store_count > 1)
)
SELECT
    customer_name,
    country_name,
    city_name,
    payment_date,
    daily_amount,
    payment_count,
    ROUND(deviation_personal, 2) AS deviation_personal,
    ROUND(deviation_country, 2) AS deviation_country,
    staff_count,
    store_count,
    RANK() OVER (
        PARTITION BY country_name
        ORDER BY daily_amount DESC
    ) AS country_rank
FROM suspicious_events
ORDER BY country_name, country_rank;