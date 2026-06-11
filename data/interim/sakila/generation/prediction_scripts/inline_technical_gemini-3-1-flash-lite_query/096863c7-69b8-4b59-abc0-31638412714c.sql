WITH daily_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS pay_date,
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
              AND prev.pay_date >= DATE(dcs.pay_date, '-30 days')
              AND prev.pay_date < dcs.pay_date
        ) AS avg_prev_30
    FROM daily_customer_stats AS dcs
),
country_daily_avg AS (
    SELECT
        c.c01 AS country_id,
        dcs.pay_date,
        AVG(dcs.daily_sum) AS country_avg_daily
    FROM daily_customer_stats AS dcs
    JOIN cus AS cu ON cu.h01 = dcs.customer_id
    JOIN adr AS a ON a.e01 = cu.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS c ON c.c01 = ct.d03
    GROUP BY c.c01, dcs.pay_date
),
suspicious_events AS (
    SELECT
        ch.*,
        cu.h03 || ' ' || cu.h04 AS customer_name,
        cnt.c02 AS country_name,
        ct.d02 AS city_name,
        cnt.c01 AS country_id,
        cda.country_avg_daily
    FROM customer_history AS ch
    JOIN cus AS cu ON cu.h01 = ch.customer_id
    JOIN adr AS a ON a.e01 = cu.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS cnt ON cnt.c01 = ct.d03
    JOIN country_daily_avg AS cda ON cda.country_id = cnt.c01 AND cda.pay_date = ch.pay_date
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
FROM suspicious_events
ORDER BY country_name, country_rank;