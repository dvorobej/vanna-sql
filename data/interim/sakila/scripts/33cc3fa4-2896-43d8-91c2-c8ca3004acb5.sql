WITH payment_enriched AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        p.p04 AS rental_id,
        p.p05 AS amount,
        p.p06 AS payment_ts,
        date(p.p06) AS payment_day,
        ROW_NUMBER() OVER (
            PARTITION BY p.p02, date(p.p06)
            ORDER BY p.p06 DESC, p.p01 DESC
        ) AS rn_last
    FROM pay AS p
),
daily_payments AS (
    SELECT
        customer_id,
        payment_day,
        COUNT(*) AS daily_payment_count,
        SUM(amount) AS daily_payment_amount
    FROM payment_enriched
    GROUP BY customer_id, payment_day
),
daily_with_history AS (
    SELECT
        dp.customer_id,
        dp.payment_day,
        dp.daily_payment_count,
        dp.daily_payment_amount,
        (
            SELECT AVG(dp2.daily_payment_count)
            FROM daily_payments AS dp2
            WHERE dp2.customer_id = dp.customer_id
              AND dp2.payment_day >= date(dp.payment_day, '-30 day')
              AND dp2.payment_day < dp.payment_day
        ) AS avg_30d_payment_count,
        (
            SELECT AVG(dp2.daily_payment_amount)
            FROM daily_payments AS dp2
            WHERE dp2.customer_id = dp.customer_id
              AND dp2.payment_day >= date(dp.payment_day, '-30 day')
              AND dp2.payment_day < dp.payment_day
        ) AS avg_30d_payment_amount
    FROM daily_payments AS dp
),
last_payment_staff AS (
    SELECT
        customer_id,
        payment_day,
        payment_id AS last_payment_id,
        payment_ts AS last_payment_ts,
        staff_id AS last_staff_id
    FROM payment_enriched
    WHERE rn_last = 1
),
day_rentals AS (
    SELECT DISTINCT
        p.p02 AS customer_id,
        date(p.p06) AS payment_day,
        r.q01 AS rental_id,
        r.q02 AS rental_ts,
        r.q05 AS return_ts,
        f.i07 AS rental_duration_days
    FROM pay AS p
    JOIN ren AS r
        ON r.q01 = p.p04
    JOIN inv AS i
        ON i.n01 = r.q03
    JOIN flm AS f
        ON f.i01 = i.n02
    WHERE p.p04 IS NOT NULL
),
rental_stats AS (
    SELECT
        customer_id,
        payment_day,
        COUNT(*) AS linked_rental_count,
        CAST(
            SUM(
                CASE
                    WHEN return_ts IS NOT NULL
                     AND return_ts > datetime(rental_ts, '+' || rental_duration_days || ' days')
                    THEN 1
                    ELSE 0
                END
            ) AS REAL
        ) / NULLIF(
            SUM(CASE WHEN return_ts IS NOT NULL THEN 1 ELSE 0 END),
            0
        ) AS overdue_return_share
    FROM day_rentals
    GROUP BY customer_id, payment_day
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS customer_first_name,
        c.h04 AS customer_last_name,
        c.h02 AS customer_store_id,
        city.d01 AS city_id,
        city.d02 AS city_name,
        country.c01 AS country_id,
        country.c02 AS country_name
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS city
        ON city.d01 = a.e05
    JOIN cnt AS country
        ON country.c01 = city.d03
),
ranked AS (
    SELECT
        dwh.customer_id,
        cg.customer_first_name,
        cg.customer_last_name,
        cg.country_id,
        cg.country_name,
        cg.city_id,
        cg.city_name,
        cg.customer_store_id,
        dwh.payment_day,
        dwh.daily_payment_count,
        dwh.daily_payment_amount,
        dwh.avg_30d_payment_count,
        dwh.avg_30d_payment_amount,
        DENSE_RANK() OVER (
            PARTITION BY cg.country_id, dwh.payment_day
            ORDER BY dwh.daily_payment_amount DESC
        ) AS country_day_amount_rank
    FROM daily_with_history AS dwh
    JOIN customer_geo AS cg
        ON cg.customer_id = dwh.customer_id
)
SELECT
    r.customer_id,
    r.customer_first_name,
    r.customer_last_name,
    r.country_name,
    r.city_name,
    r.payment_day,
    r.daily_payment_count,
    ROUND(r.daily_payment_amount, 2) AS daily_payment_amount,
    ROUND(r.avg_30d_payment_count, 2) AS avg_30d_payment_count,
    ROUND(r.avg_30d_payment_amount, 2) AS avg_30d_payment_amount,
    r.customer_store_id,
    s.o07 AS last_payment_staff_store_id,
    lps.last_staff_id,
    s.o02 AS last_staff_first_name,
    s.o03 AS last_staff_last_name,
    lps.last_payment_id,
    lps.last_payment_ts,
    COALESCE(rs.linked_rental_count, 0) AS linked_rental_count,
    ROUND(rs.overdue_return_share, 4) AS overdue_return_share,
    r.country_day_amount_rank,
    CASE
        WHEN r.avg_30d_payment_amount IS NOT NULL
         AND r.daily_payment_amount > r.avg_30d_payment_amount * 3
         AND r.daily_payment_count >= 5
        THEN 'amount_over_3x_and_count_at_least_5'
        WHEN r.avg_30d_payment_amount IS NOT NULL
         AND r.daily_payment_amount > r.avg_30d_payment_amount * 3
        THEN 'amount_over_3x'
        WHEN r.daily_payment_count >= 5
        THEN 'count_at_least_5'
    END AS suspicious_reason
FROM ranked AS r
JOIN last_payment_staff AS lps
    ON lps.customer_id = r.customer_id
   AND lps.payment_day = r.payment_day
JOIN stf AS s
    ON s.o01 = lps.last_staff_id
LEFT JOIN rental_stats AS rs
    ON rs.customer_id = r.customer_id
   AND rs.payment_day = r.payment_day
WHERE (
        r.avg_30d_payment_amount IS NOT NULL
        AND r.daily_payment_amount > r.avg_30d_payment_amount * 3
      )
   OR r.daily_payment_count >= 5
ORDER BY
    r.payment_day,
    r.country_name,
    r.country_day_amount_rank,
    r.daily_payment_amount DESC;