WITH daily_customer_activity AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
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
        AVG(dca.daily_amount) OVER (
            PARTITION BY dca.customer_id 
            ORDER BY dca.payment_date 
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS personal_avg_30d
    FROM daily_customer_activity AS dca
),
country_daily_stats AS (
    SELECT
        ct.d03 AS country_id,
        dca.payment_date,
        AVG(dca.daily_amount) AS country_avg_daily_amount
    FROM daily_customer_activity AS dca
    JOIN cus AS c ON c.h01 = dca.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    GROUP BY ct.d03, dca.payment_date
),
suspicious_activity AS (
    SELECT
        ch.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        cds.country_avg_daily_amount,
        (ch.daily_amount - ch.personal_avg_30d) AS diff_personal,
        (ch.daily_amount - cds.country_avg_daily_amount) AS diff_country
    FROM customer_history AS ch
    JOIN cus AS c ON c.h01 = ch.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS cty ON cty.d01 = a.e05
    JOIN cnt AS cnt ON cnt.c01 = cty.d03
    JOIN country_daily_stats AS cds ON cds.country_id = cnt.c01 AND cds.payment_date = ch.payment_date
    WHERE ch.personal_avg_30d IS NOT NULL
      AND ch.daily_amount > ch.personal_avg_30d
      AND ch.daily_amount > cds.country_avg_daily_amount
)
SELECT
    customer_name,
    country_name,
    city_name,
    payment_date,
    daily_amount,
    daily_count,
    staff_count,
    store_count,
    ROUND(personal_avg_30d, 2) AS personal_avg_30d,
    ROUND(country_avg_daily_amount, 2) AS country_avg_daily_amount,
    ROUND(diff_personal, 2) AS diff_personal,
    ROUND(diff_country, 2) AS diff_country,
    RANK() OVER (PARTITION BY country_name, payment_date ORDER BY daily_amount DESC) AS country_rank
FROM suspicious_activity
ORDER BY payment_date DESC, country_rank ASC;