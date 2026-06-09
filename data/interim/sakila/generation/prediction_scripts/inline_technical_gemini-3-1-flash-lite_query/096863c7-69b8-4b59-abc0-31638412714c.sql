WITH daily_customer_activity AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS activity_date,
        SUM(p.p05) AS daily_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, DATE(p.p06)
),
customer_stats AS (
    SELECT
        dca.*,
        AVG(dca.daily_amount) OVER (
            PARTITION BY dca.customer_id
            ORDER BY dca.activity_date
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS personal_avg_30d
    FROM daily_customer_activity AS dca
),
country_daily_avg AS (
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
country_avg_stats AS (
    SELECT
        cg.country_id,
        dca.activity_date,
        AVG(dca.daily_amount) AS country_avg_daily_amount
    FROM daily_customer_activity AS dca
    JOIN country_daily_avg AS cg ON cg.customer_id = dca.customer_id
    GROUP BY cg.country_id, dca.activity_date
),
suspicious_activity AS (
    SELECT
        cs.*,
        cg.customer_name,
        cg.country_name,
        cg.city_name,
        cas.country_avg_daily_amount
    FROM customer_stats AS cs
    JOIN country_daily_avg AS cg ON cg.customer_id = cs.customer_id
    JOIN country_avg_stats AS cas ON cas.country_id = cg.country_id AND cas.activity_date = cs.activity_date
    WHERE cs.personal_avg_30d IS NOT NULL
      AND cs.daily_amount > (cs.personal_avg_30d * 3)
      AND cs.daily_amount > cas.country_avg_daily_amount
      AND (cs.staff_count > 1 OR cs.store_count > 1)
)
SELECT
    customer_name,
    country_name,
    city_name,
    activity_date,
    daily_amount,
    payment_count,
    ROUND(daily_amount - personal_avg_30d, 2) AS deviation_from_personal_avg,
    ROUND(daily_amount - country_avg_daily_amount, 2) AS deviation_from_country_avg,
    staff_count,
    store_count,
    RANK() OVER (
        PARTITION BY country_name
        ORDER BY daily_amount DESC
    ) AS country_suspicion_rank
FROM suspicious_activity
ORDER BY country_name, country_suspicion_rank;