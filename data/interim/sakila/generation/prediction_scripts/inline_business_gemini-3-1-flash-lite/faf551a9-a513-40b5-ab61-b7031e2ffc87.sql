WITH daily_customer_activity AS (
    SELECT
        p.p02 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        co.c02 AS country,
        ci.d02 AS city,
        p.p03 AS staff_id,
        s.o07 AS store_id,
        DATE(p.p06) AS payment_date,
        SUM(p.p05) AS daily_amount,
        COUNT(*) AS daily_count
    FROM pay p
    JOIN cus c ON c.h01 = p.p02
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ci ON ci.d01 = a.e05
    JOIN cnt co ON co.c01 = ci.d03
    JOIN stf s ON s.o01 = p.p03
    GROUP BY p.p02, c.h03, c.h04, co.c02, ci.d02, p.p03, s.o07, DATE(p.p06)
),
daily_stats AS (
    SELECT
        customer_id,
        first_name,
        last_name,
        country,
        city,
        store_id,
        payment_date,
        SUM(daily_amount) AS total_daily_amount,
        SUM(daily_count) AS total_daily_count
    FROM daily_customer_activity
    GROUP BY customer_id, first_name, last_name, country, city, store_id, payment_date
),
history_stats AS (
    SELECT
        ds.*,
        (
            SELECT AVG(ds2.total_daily_amount)
            FROM daily_stats ds2
            WHERE ds2.customer_id = ds.customer_id
              AND ds2.payment_date >= DATE(ds.payment_date, '-30 days')
              AND ds2.payment_date < ds.payment_date
        ) AS avg_30d_amount,
        (
            SELECT AVG(ds3.total_daily_amount)
            FROM daily_stats ds3
            WHERE ds3.country = ds.country
              AND ds3.payment_date = ds.payment_date
        ) AS country_avg_daily_amount
    FROM daily_stats ds
),
suspicious_spikes AS (
    SELECT
        *,
        (total_daily_amount - avg_30d_amount) AS deviation
    FROM history_stats
    WHERE avg_30d_amount > 0
      AND total_daily_amount > (3 * avg_30d_amount)
      AND total_daily_amount > country_avg_daily_amount
)
SELECT
    payment_date,
    first_name,
    last_name,
    country,
    city,
    store_id,
    total_daily_count,
    ROUND(total_daily_amount, 2) AS total_daily_amount,
    ROUND(avg_30d_amount, 2) AS avg_30d_amount,
    ROUND(deviation, 2) AS deviation,
    RANK() OVER (PARTITION BY country ORDER BY deviation DESC) AS country_spike_rank
FROM suspicious_spikes
ORDER BY country, country_spike_rank;