WITH daily_customer_activity AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS activity_date,
        SUM(p.p05) AS daily_amount,
        COUNT(*) AS daily_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, DATE(p.p06)
),
customer_history AS (
    SELECT
        dca.*,
        (
            SELECT AVG(dca2.daily_amount)
            FROM daily_customer_activity AS dca2
            WHERE dca2.customer_id = dca.customer_id
              AND dca2.activity_date >= DATE(dca.activity_date, '-30 days')
              AND dca2.activity_date < dca.activity_date
        ) AS personal_avg_30d
    FROM daily_customer_activity AS dca
),
country_daily_stats AS (
    SELECT
        c.h01 AS customer_id,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        c.h03 || ' ' || c.h04 AS customer_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
country_avg AS (
    SELECT
        cds.country_id,
        dca.activity_date,
        AVG(dca.daily_amount) AS country_avg_daily_amount
    FROM daily_customer_activity AS dca
    JOIN country_daily_stats AS cds ON cds.customer_id = dca.customer_id
    GROUP BY cds.country_id, dca.activity_date
),
suspicious_activity AS (
    SELECT
        ch.*,
        cds.customer_name,
        cds.country_name,
        cds.city_name,
        ca.country_avg_daily_amount,
        (ch.daily_amount - ch.personal_avg_30d) AS personal_deviation,
        (ch.daily_amount - ca.country_avg_daily_amount) AS country_deviation,
        RANK() OVER (
            PARTITION BY cds.country_id, ch.activity_date
            ORDER BY ch.daily_amount DESC
        ) AS country_rank
    FROM customer_history AS ch
    JOIN country_daily_stats AS cds ON cds.customer_id = ch.customer_id
    JOIN country_avg AS ca ON ca.country_id = cds.country_id AND ca.activity_date = ch.activity_date
    WHERE ch.personal_avg_30d IS NOT NULL
      AND ch.daily_amount > ch.personal_avg_30d * 2
      AND ch.daily_amount > ca.country_avg_daily_amount * 1.5
)
SELECT
    customer_name,
    country_name,
    city_name,
    activity_date,
    daily_amount,
    daily_count,
    ROUND(personal_avg_30d, 2) AS personal_avg_30d,
    ROUND(country_avg_daily_amount, 2) AS country_avg_daily_amount,
    ROUND(personal_deviation, 2) AS personal_deviation,
    ROUND(country_deviation, 2) AS country_deviation,
    staff_count,
    store_count,
    country_rank
FROM suspicious_activity
ORDER BY country_name, activity_date, country_rank;