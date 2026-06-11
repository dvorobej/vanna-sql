WITH daily_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        SUM(p.p05) AS daily_sum,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, DATE(p.p06)
),
customer_history AS (
    SELECT
        dcs.*,
        (
            SELECT AVG(prev.daily_sum)
            FROM daily_customer_stats AS prev
            WHERE prev.customer_id = dcs.customer_id
              AND prev.payment_date >= DATE(dcs.payment_date, '-30 days')
              AND prev.payment_date < dcs.payment_date
        ) AS avg_prev_30
    FROM daily_customer_stats AS dcs
),
country_daily_avg AS (
    SELECT
        ct.c01 AS country_id,
        dcs.payment_date,
        AVG(dcs.daily_sum) AS country_avg_daily
    FROM daily_customer_stats AS dcs
    JOIN cus AS c ON c.h01 = dcs.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS cy ON cy.d01 = a.e05
    JOIN cnt AS ct ON ct.c01 = cy.d03
    GROUP BY ct.c01, dcs.payment_date
),
suspicious_spikes AS (
    SELECT
        ch.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        cnt.c01 AS country_id,
        cda.country_avg_daily
    FROM customer_history AS ch
    JOIN cus AS c ON c.h01 = ch.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS cty ON cty.d01 = a.e05
    JOIN cnt AS cnt ON cnt.c01 = cty.d03
    JOIN country_daily_avg AS cda ON cda.country_id = cnt.c01 AND cda.payment_date = ch.payment_date
    WHERE ch.avg_prev_30 > 0
      AND ch.daily_sum > (3 * ch.avg_prev_30)
      AND ch.daily_sum > cda.country_avg_daily
      AND (ch.staff_count > 1 OR ch.store_count > 1)
)
SELECT
    customer_name,
    country_name,
    city_name,
    payment_date,
    daily_sum,
    payment_count,
    ROUND(daily_sum - avg_prev_30, 2) AS deviation_from_personal_avg,
    ROUND(daily_sum - country_avg_daily, 2) AS deviation_from_country_avg,
    staff_count,
    store_count,
    RANK() OVER (
        PARTITION BY country_id
        ORDER BY daily_sum DESC
    ) AS country_rank
FROM suspicious_spikes
ORDER BY country_name, country_rank;