WITH daily_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS pay_date,
        SUM(p.p05) AS daily_sum,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT stf.o07) AS store_count
    FROM pay p
    JOIN stf ON stf.o01 = p.p03
    GROUP BY p.p02, DATE(p.p06)
),
customer_history AS (
    SELECT
        dcs.*,
        (
            SELECT AVG(h.daily_sum)
            FROM daily_customer_stats h
            WHERE h.customer_id = dcs.customer_id
              AND h.pay_date >= DATE(dcs.pay_date, '-30 days')
              AND h.pay_date < dcs.pay_date
        ) AS avg_prev_30
    FROM daily_customer_stats dcs
),
country_daily_avg AS (
    SELECT
        cty.d03 AS country_id,
        dcs.pay_date,
        AVG(dcs.daily_sum) AS country_avg_daily
    FROM daily_customer_stats dcs
    JOIN cus ON cus.h01 = dcs.customer_id
    JOIN adr ON adr.e01 = cus.h06
    JOIN cty ON cty.d01 = adr.e05
    GROUP BY cty.d03, dcs.pay_date
),
suspicious_events AS (
    SELECT
        ch.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        cnt.c01 AS country_id,
        cda.country_avg_daily
    FROM customer_history ch
    JOIN cus c ON c.h01 = ch.customer_id
    JOIN adr ON adr.e01 = c.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
    JOIN country_daily_avg cda ON cda.country_id = cnt.c01 AND cda.pay_date = ch.pay_date
    WHERE ch.avg_prev_30 > 0
      AND ch.daily_sum > 3 * ch.avg_prev_30
      AND ch.daily_sum > cda.country_avg_daily
      AND (ch.staff_count > 1 OR ch.store_count > 1)
)
SELECT
    customer_name,
    country_name,
    city_name,
    pay_date,
    ROUND(daily_sum, 2) AS daily_sum,
    payment_count,
    ROUND(daily_sum - avg_prev_30, 2) AS deviation_from_personal_avg,
    ROUND(daily_sum - country_avg_daily, 2) AS deviation_from_country_avg,
    staff_count,
    store_count,
    RANK() OVER (
        PARTITION BY country_id
        ORDER BY daily_sum DESC
    ) AS country_suspicion_rank
FROM suspicious_events
ORDER BY country_name, country_suspicion_rank;