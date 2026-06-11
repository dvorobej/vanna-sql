WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS customer_first_name,
        c.h04 AS customer_last_name,
        ct.d02 AS city_name,
        cnt.c02 AS country_name,
        cnt.c01 AS country_id,
        c.h06 AS customer_address_id
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ct
        ON ct.d01 = a.e05
    JOIN cnt
        ON cnt.c01 = ct.d03
),
daily_payments AS (
    SELECT
        cg.customer_id,
        cg.customer_first_name,
        cg.customer_last_name,
        cg.city_name,
        cg.country_id,
        cg.country_name,
        date(p.p06) AS payment_day,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS daily_amount,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT s.o07) AS distinct_store_count
    FROM pay AS p
    JOIN customer_geo AS cg
        ON cg.customer_id = p.p02
    JOIN stf AS s
        ON s.o01 = p.p03
    GROUP BY
        cg.customer_id,
        cg.customer_first_name,
        cg.customer_last_name,
        cg.city_name,
        cg.country_id,
        cg.country_name,
        date(p.p06)
),
daily_with_history AS (
    SELECT
        dp.*,
        (
            SELECT AVG(dp2.daily_amount)
            FROM daily_payments AS dp2
            WHERE dp2.customer_id = dp.customer_id
              AND dp2.payment_day >= date(dp.payment_day, '-30 days')
              AND dp2.payment_day < dp.payment_day
        ) AS personal_avg_day_amount_30d,
        (
            SELECT AVG(dp2.payment_count)
            FROM daily_payments AS dp2
            WHERE dp2.customer_id = dp.customer_id
              AND dp2.payment_day >= date(dp.payment_day, '-30 days')
              AND dp2.payment_day < dp.payment_day
        ) AS personal_avg_day_payment_count_30d
    FROM daily_payments AS dp
),
country_daily_avg AS (
    SELECT
        country_id,
        payment_day,
        AVG(daily_amount) AS country_avg_day_amount
    FROM daily_payments
    GROUP BY
        country_id,
        payment_day
),
scored AS (
    SELECT
        dwh.customer_id,
        dwh.customer_first_name,
        dwh.customer_last_name,
        dwh.city_name,
        dwh.country_id,
        dwh.country_name,
        dwh.payment_day,
        dwh.payment_count,
        dwh.daily_amount,
        dwh.distinct_staff_count,
        dwh.distinct_store_count,
        dwh.personal_avg_day_amount_30d,
        cdca.country_avg_day_amount,
        (dwh.daily_amount - dwh.personal_avg_day_amount_30d) AS deviation_from_personal_avg,
        (dwh.daily_amount - cdca.country_avg_day_amount) AS deviation_from_country_avg,
        RANK() OVER (
            PARTITION BY dwh.country_id
            ORDER BY dwh.daily_amount DESC
        ) AS suspicious_day_rank_in_country
    FROM daily_with_history AS dwh
    JOIN country_daily_avg AS cdca
        ON cdca.country_id = dwh.country_id
       AND cdca.payment_day = dwh.payment_day
    WHERE dwh.personal_avg_day_amount_30d IS NOT NULL
      AND cdca.country_avg_day_amount IS NOT NULL
)
SELECT
    customer_id,
    customer_first_name,
    customer_last_name,
    city_name,
    country_name,
    payment_day,
    payment_count,
    ROUND(daily_amount, 2) AS daily_amount,
    ROUND(personal_avg_day_amount_30d, 2) AS personal_avg_day_amount_30d,
    ROUND(country_avg_day_amount, 2) AS country_avg_day_amount,
    ROUND(deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
    ROUND(deviation_from_country_avg, 2) AS deviation_from_country_avg,
    distinct_staff_count,
    distinct_store_count,
    suspicious_day_rank_in_country
FROM scored
WHERE daily_amount > 3 * personal_avg_day_amount_30d
  AND daily_amount > country_avg_day_amount
ORDER BY
    country_name,
    suspicious_day_rank_in_country,
    payment_day,
    daily_amount DESC,
    customer_id;