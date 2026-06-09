WITH payment_geo AS (
    SELECT
        p.p02 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        c.h02 AS home_store_id,
        co.c01 AS country_id,
        co.c02 AS country_name,
        ci.d02 AS city_name,
        p.p06 AS payment_ts,
        date(p.p06) AS payment_day,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p03 AS staff_id,
        s.o07 AS store_id
    FROM pay p
    JOIN cus c ON c.h01 = p.p02
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ci ON ci.d01 = a.e05
    JOIN cnt co ON co.c01 = ci.d03
    JOIN stf s ON s.o01 = p.p03
),
daily_in_store_country AS (
    SELECT
        customer_id,
        customer_name,
        country_id,
        country_name,
        city_name,
        store_id,
        payment_day,
        COUNT(*) AS payment_count,
        SUM(payment_amount) AS day_sum
    FROM payment_geo
    GROUP BY
        customer_id, customer_name, country_id, country_name, city_name, store_id, payment_day
),
with_personal_history AS (
    SELECT
        d.*,
        (
            SELECT AVG(d2.day_sum)
            FROM daily_in_store_country d2
            WHERE d2.customer_id = d.customer_id
              AND d2.country_id = d.country_id
              AND d2.store_id = d.store_id
              AND d2.payment_day >= date(d.payment_day, '-30 day')
              AND d2.payment_day < d.payment_day
        ) AS avg_prev_30d_day_sum
    FROM daily_in_store_country d
),
with_country_exception AS (
    SELECT
        w.*,
        (
            SELECT AVG(w2.day_sum)
            FROM daily_in_store_country w2
            WHERE w2.country_id = w.country_id
              AND w2.store_id = w.store_id
              AND w2.payment_day >= date(w.payment_day, '-30 day')
              AND w2.payment_day < w2.payment_day
        ) AS avg_country_prev_30d_day_sum -- not used;