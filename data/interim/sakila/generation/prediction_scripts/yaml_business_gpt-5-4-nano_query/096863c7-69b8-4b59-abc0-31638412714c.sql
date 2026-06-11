WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS pay_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT COALESCE(p.p04, -1)) AS store_count
    FROM pay AS p
    GROUP BY
        p.p02,
        DATE(p.p06)
),
calendar_daily AS (
    SELECT
        dp.customer_id,
        dp.pay_date,
        dp.payment_count,
        dp.day_amount,
        dp.staff_count,
        dp.store_count,
        (
            SELECT AVG(prev.day_amount)
            FROM daily_payments AS prev
            WHERE prev.customer_id = dp.customer_id
              AND prev.pay_date >= DATE(dp.pay_date, '-30 day')
              AND prev.pay_date < dp.pay_date
        ) AS personal_avg_prev_30
    FROM daily_payments AS dp
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        cnt.c02 AS country_name,
        cty.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty
        ON cty.d01 = a.e05
    JOIN cnt
        ON cnt.c01 = cty.d03
),
country_daily_avg AS (
    SELECT
        dp.pay_date,
        cg.country_name,
        AVG(dp.day_amount) AS country_avg_day_amount
    FROM daily_payments AS dp
    JOIN customer_geo AS cg
        ON cg.customer_id = dp.customer_id
    GROUP BY
        dp.pay_date,
        cg.country_name
),
candidate_days AS (
    SELECT
        cd.customer_id,
        cg.city_name,
        cg.country_name,
        cd.pay_date,
        cd.payment_count,
        cd.day_amount,
        cd.personal_avg_prev_30,
        (cd.day_amount - cd.personal_avg_prev_30) AS deviation_personal_avg,
        cda.country_avg_day_amount,
        (cd.day_amount - cda.country_avg_day_amount) AS deviation_country_avg,
        cd.staff_count,
        cd.store_count
    FROM calendar_daily AS cd
    JOIN customer_geo AS cg
        ON cg.customer_id = cd.customer_id
    JOIN country_daily_avg AS cda
        ON cda.pay_date = cd.pay_date
       AND cda.country_name = cg.country_name
    WHERE cd.personal_avg_prev_30 IS NOT NULL
      AND cd.personal_avg_prev_30 > 0
      AND cd.day_amount > 3 * cd.personal_avg_prev_30
      AND cd.day_amount > cda.country_avg_day_amount
      AND (cd.staff_count > 1 OR cd.store_count > 1)
),
ranked AS (
    SELECT
        cd.*,
        DENSE_RANK() OVER (
            PARTITION BY cd.country_name
            ORDER BY cd.day_amount DESC
        ) AS suspicious_amount_rank_in_country
    FROM candidate_days AS cd
)
SELECT
    customer_id,
    country_name AS country,
    city_name AS city,
    pay_date AS date,
    ROUND(day_amount, 2) AS day_amount,
    payment_count,
    ROUND(deviation_personal_avg, 2) AS deviation_personal_avg,
    ROUND(deviation_country_avg, 2) AS deviation_country_avg,
    staff_count AS distinct_staff_count,
    store_count AS distinct_store_count,
    suspicious_amount_rank_in_country
FROM ranked
ORDER BY
    country,
    suspicious_amount_rank_in_country,
    date,
    customer_id;