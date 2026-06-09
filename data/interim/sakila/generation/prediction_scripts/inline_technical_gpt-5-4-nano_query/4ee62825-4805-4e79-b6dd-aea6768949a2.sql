WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        city.d02 AS city_name,
        co.c02 AS country_name,
        c.h06 AS address_id,
        c.h02 AS home_store_id
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS city ON city.d01 = a.e05
    JOIN cnt AS co ON co.c01 = city.d03
),
daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        cg.customer_name,
        cg.city_name,
        cg.country_name,
        date(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        MIN(p.p06) AS first_payment_ts,
        MAX(p.p06) AS last_payment_ts,
        MAX(CAST(p.p05 AS REAL)) AS max_payment_amount
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    JOIN customer_geo AS cg ON cg.customer_id = p.p02
    GROUP BY
        p.p02,
        cg.customer_name,
        cg.city_name,
        cg.country_name,
        date(p.p06)
),
daily_with_personal_avg AS (
    SELECT
        dp.*,
        (
            SELECT AVG(dp_prev.day_amount)
            FROM daily_payments AS dp_prev
            WHERE dp_prev.customer_id = dp.customer_id
              AND dp_prev.payment_date >= date(dp.payment_date, '-30 day')
              AND dp_prev.payment_date < dp.payment_date
        ) AS personal_avg_daily_prev_30d
    FROM daily_payments AS dp
),
country_days_ranked AS (
    SELECT
        dp.country_name,
        dp.payment_date,
        dp.day_amount,
        ROW_NUMBER() OVER (
            PARTITION BY dp.country_name
            ORDER BY dp.day_amount
        ) AS rn_asc,
        COUNT(*) OVER (PARTITION BY dp.country_name) AS cnt_days
    FROM daily_payments AS dp
),
country_p95 AS (
    SELECT
        country_name,
        MAX(day_amount) AS p95_day_amount
    FROM country_days_ranked
    WHERE rn_asc >= CAST(0.95 * (cnt_days) + 0.5 AS INT)
    GROUP BY country_name
),
scored AS (
    SELECT
        dwp.*,
        c95.p95_day_amount,
        (CASE WHEN dwp.personal_avg_daily_prev_30d IS NOT NULL AND dwp.personal_avg_daily_prev_30d > 0
              THEN dwp.day_amount / dwp.personal_avg_daily_prev_30d
              ELSE NULL
         END) AS personal_ratio
    FROM daily_with_personal_avg AS dwp
    JOIN country_p95 AS c95
      ON c95.country_name = dwp.country_name
    WHERE dwp.personal_avg_daily_prev_30d IS NOT NULL
)
SELECT
    s.customer_id,
    s.customer_name,
    s.city_name,
    s.country_name,
    s.payment_date AS suspicious_date,
    s.payment_count,
    ROUND(s.day_amount, 2) AS day_amount,
    s.staff_count AS distinct_staff_count,
    s.store_count AS distinct_store_count,
    s.first_payment_ts AS first_operation_ts,
    s.last_payment_ts AS last_operation_ts,
    ROUND(s.max_payment_amount, 2) AS max_payment_amount,
    ROUND(s.personal_ratio, 3) AS ratio_to_personal_avg,
    RANK() OVER (
        PARTITION BY s.country_name
        ORDER BY (s.day_amount - s.personal_avg_daily_prev_30d) DESC, s.day_amount DESC, s.customer_id
    ) AS suspicion_rank_in_country
FROM scored AS s
WHERE s.payment_count >= 3
  AND s.staff_count >= 2
  AND s.day_amount > 3.0 * s.personal_avg_daily_prev_30d
  AND s.day_amount > s.p95_day_amount
ORDER BY
    s.country_name,
    suspicion_rank_in_country,
    s.day_amount DESC,
    s.customer_id,
    s.payment_date;