WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
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
daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        cg.customer_name,
        cg.country_id,
        cg.country_name,
        cg.city_name,
        date(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS day_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        group_concat(DISTINCT s.o02 || ' ' || s.o03) AS staff_list
    FROM pay AS p
    JOIN stf AS s
        ON s.o01 = p.p03
    JOIN customer_geo AS cg
        ON cg.customer_id = p.p02
    GROUP BY
        p.p02,
        cg.customer_name,
        cg.country_id,
        cg.country_name,
        cg.city_name,
        date(p.p06)
),
daily_with_avg AS (
    SELECT
        dp.*,
        COALESCE((
            SELECT SUM(prev.day_amount) / 30.0
            FROM daily_payments AS prev
            WHERE prev.customer_id = dp.customer_id
              AND prev.payment_date >= date(dp.payment_date, '-30 day')
              AND prev.payment_date < dp.payment_date
        ), 0.0) AS personal_avg_30d
    FROM daily_payments AS dp
),
country_percentile AS (
    SELECT
        country_id,
        MIN(day_amount) AS p95_day_amount
    FROM (
        SELECT
            country_id,
            day_amount,
            ROW_NUMBER() OVER (
                PARTITION BY country_id
                ORDER BY day_amount
            ) AS rn,
            COUNT(*) OVER (
                PARTITION BY country_id
            ) AS cnt
        FROM daily_payments
    ) AS ranked_country_days
    WHERE rn >= ((95 * cnt + 99) / 100)
    GROUP BY country_id
),
suspicious_cases AS (
    SELECT
        dwa.*,
        cp.p95_day_amount,
        dwa.day_amount - dwa.personal_avg_30d AS deviation_from_personal_avg
    FROM daily_with_avg AS dwa
    JOIN country_percentile AS cp
        ON cp.country_id = dwa.country_id
    WHERE dwa.payment_count >= 3
      AND (dwa.staff_count > 1 OR dwa.store_count > 1)
      AND dwa.day_amount > 2.0 * dwa.personal_avg_30d
      AND dwa.day_amount > cp.p95_day_amount
)
SELECT
    customer_id,
    customer_name,
    country_name,
    city_name,
    payment_date,
    payment_count,
    ROUND(day_amount, 2) AS day_amount,
    staff_list,
    ROUND(deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
    RANK() OVER (
        PARTITION BY country_id
        ORDER BY
            deviation_from_personal_avg DESC,
            day_amount DESC,
            payment_count DESC,
            customer_id
    ) AS suspicion_rank_in_country
FROM suspicious_cases
ORDER BY
    country_name,
    suspicion_rank_in_country,
    payment_date,
    customer_id;