WITH daily_customer_activity AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS daily_sum,
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
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        cnt.c01 AS country_id
    FROM cus AS c
    JOIN adr ON adr.e01 = c.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
daily_with_metrics AS (
    SELECT
        dca.*,
        cg.customer_name,
        cg.country_name,
        cg.city_name,
        cg.country_id,
        (
            SELECT AVG(dca2.daily_sum)
            FROM daily_customer_activity AS dca2
            WHERE dca2.customer_id = dca.customer_id
              AND dca2.payment_date >= DATE(dca.payment_date, '-30 days')
              AND dca2.payment_date < dca.payment_date
        ) AS personal_avg_30d
    FROM daily_customer_activity AS dca
    JOIN customer_geo AS cg ON cg.customer_id = dca.customer_id
),
country_daily_avg AS (
    SELECT
        country_id,
        AVG(daily_sum) AS country_avg_daily_sum
    FROM daily_customer_activity AS dca
    JOIN customer_geo AS cg ON cg.customer_id = dca.customer_id
    GROUP BY country_id
),
suspicious_days AS (
    SELECT
        dwm.*,
        cda.country_avg_daily_sum,
        dwm.daily_sum - dwm.personal_avg_30d AS deviation_personal,
        dwm.daily_sum - cda.country_avg_daily_sum AS deviation_country
    FROM daily_with_metrics AS dwm
    JOIN country_daily_avg AS cda ON cda.country_id = dwm.country_id
    WHERE dwm.personal_avg_30d > 0
      AND dwm.daily_sum > 3 * dwm.personal_avg_30d
      AND dwm.daily_sum > cda.country_avg_daily_sum
)
SELECT
    customer_id,
    country_name,
    city_name,
    payment_date,
    ROUND(daily_sum, 2) AS daily_sum,
    payment_count,
    ROUND(deviation_personal, 2) AS deviation_from_personal_avg,
    ROUND(deviation_country, 2) AS deviation_from_country_avg,
    staff_count,
    store_count,
    RANK() OVER (
        PARTITION BY country_id
        ORDER BY daily_sum DESC
    ) AS country_rank
FROM suspicious_days
ORDER BY
    country_name,
    country_rank,
    payment_date;