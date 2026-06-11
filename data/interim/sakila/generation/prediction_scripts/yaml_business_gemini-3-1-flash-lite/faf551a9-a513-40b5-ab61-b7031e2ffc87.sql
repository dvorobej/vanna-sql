WITH daily_customer_activity AS (
    SELECT
        p.p02 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        co.c02 AS country,
        ci.d02 AS city,
        c.h02 AS store_id,
        DATE(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS daily_amount
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
    GROUP BY p.p02, c.h03, c.h04, co.c02, ci.d02, c.h02, DATE(p.p06)
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
        country,
        payment_date,
        AVG(daily_amount) AS avg_country_daily_amount,
        STDEV(daily_amount) AS stddev_country_daily_amount
    FROM daily_customer_activity
    GROUP BY country, payment_date
),
suspicious_events AS (
    SELECT
        ch.*,
        (ch.daily_amount - ch.avg_30d_amount) AS deviation,
        RANK() OVER (PARTITION BY ch.country ORDER BY ch.daily_amount DESC) AS country_rank
    FROM customer_history AS ch
    JOIN country_stats AS cs ON ch.country = cs.country AND ch.payment_date = cs.payment_date
    WHERE ch.avg_30d_amount IS NOT NULL
      AND ch.daily_amount > (ch.avg_30d_amount * 3)
      AND ch.daily_amount > (cs.avg_country_daily_amount + 2 * cs.stddev_country_daily_amount)
)
SELECT
    payment_date,
    first_name,
    last_name,
    country,
    city,
    store_id,
    payment_count,
    ROUND(daily_amount, 2) AS daily_amount,
    ROUND(avg_30d_amount, 2) AS avg_30d_amount,
    ROUND(deviation, 2) AS deviation,
    country_rank
FROM suspicious_events
ORDER BY country, country_rank;