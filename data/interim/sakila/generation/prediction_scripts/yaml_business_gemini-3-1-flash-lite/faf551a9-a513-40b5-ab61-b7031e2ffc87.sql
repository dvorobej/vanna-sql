WITH daily_customer_activity AS (
    SELECT
        p.p02 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        c.h02 AS store_id,
        co.c01 AS country_id,
        co.c02 AS country_name,
        ci.d02 AS city_name,
        DATE(p.p06) AS payment_date,
        SUM(p.p05) AS daily_amount,
        COUNT(*) AS payment_count
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
    GROUP BY p.p02, c.h03, c.h04, c.h02, co.c01, co.c02, ci.d02, DATE(p.p06)
),
customer_history AS (
    SELECT
        dca.*,
        (
            SELECT AVG(h.daily_amount)
            FROM daily_customer_activity AS h
            WHERE h.customer_id = dca.customer_id
              AND h.payment_date >= DATE(dca.payment_date, '-30 days')
              AND h.payment_date < dca.payment_date
        ) AS avg_30d_amount
    FROM daily_customer_activity AS dca
),
country_stats AS (
    SELECT
        country_id,
        payment_date,
        AVG(daily_amount) AS avg_country_daily_amount,
        STDEV(daily_amount) AS stddev_country_daily_amount
    FROM daily_customer_activity
    GROUP BY country_id, payment_date
),
suspicious_events AS (
    SELECT
        ch.*,
        (ch.daily_amount - ch.avg_30d_amount) AS deviation_from_personal,
        cs.avg_country_daily_amount,
        cs.stddev_country_daily_amount
    FROM customer_history AS ch
    JOIN country_stats AS cs ON cs.country_id = ch.country_id AND cs.payment_date = ch.payment_date
    WHERE ch.avg_30d_amount IS NOT NULL
      AND ch.daily_amount > (ch.avg_30d_amount * 3)
      AND ch.daily_amount > (cs.avg_country_daily_amount + 2 * cs.stddev_country_daily_amount)
),
ranked_events AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY country_id ORDER BY daily_amount DESC) AS country_rank
    FROM suspicious_events
)
SELECT
    payment_date,
    customer_name,
    country_name,
    city_name,
    store_id,
    payment_count,
    ROUND(daily_amount, 2) AS daily_amount,
    ROUND(avg_30d_amount, 2) AS avg_30d_amount,
    ROUND(deviation_from_personal, 2) AS deviation_from_personal,
    country_rank
FROM ranked_events
ORDER BY country_name, country_rank;