WITH daily_customer_activity AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS activity_date,
        SUM(p.p05) AS daily_amount,
        COUNT(*) AS daily_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT st.o07) AS store_count
    FROM pay AS p
    JOIN stf AS st ON st.o01 = p.p03
    GROUP BY p.p02, DATE(p.p06)
),
customer_history AS (
    SELECT
        dca.*,
        AVG(dca.daily_amount) OVER (
            PARTITION BY dca.customer_id
            ORDER BY dca.activity_date
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS personal_avg_30d
    FROM daily_customer_activity AS dca
),
country_daily_stats AS (
    SELECT
        c.h01 AS customer_id,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        cty.d02 AS city_name
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
        cds.country_name,
        cds.city_name,
        ca.country_avg_daily_amount,
        (ch.daily_amount - ch.personal_avg_30d) AS diff_personal,
        (ch.daily_amount - ca.country_avg_daily_amount) AS diff_country
    FROM customer_history AS ch
    JOIN country_daily_stats AS cds ON cds.customer_id = ch.customer_id
    JOIN country_avg AS ca ON ca.country_id = cds.country_id AND ca.activity_date = ch.activity_date
    WHERE ch.personal_avg_30d IS NOT NULL
      AND ch.daily_amount > ch.personal_avg_30d * 2
      AND ch.daily_amount > ca.country_avg_daily_amount * 1.5
)
SELECT
    sa.customer_id,
    sa.activity_date,
    sa.country_name,
    sa.city_name,
    sa.daily_amount,
    sa.daily_count,
    sa.staff_count,
    sa.store_count,
    ROUND(sa.personal_avg_30d, 2) AS personal_avg_30d,
    ROUND(sa.country_avg_daily_amount, 2) AS country_avg_daily_amount,
    RANK() OVER (
        PARTITION BY sa.country_name, sa.activity_date
        ORDER BY sa.daily_amount DESC
    ) AS country_suspicion_rank
FROM suspicious_activity AS sa
ORDER BY sa.activity_date DESC, sa.country_name, country_suspicion_rank;