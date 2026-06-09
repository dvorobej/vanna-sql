WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        ci.d02 AS city_name,
        cnt.c02 AS country_name
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ci
        ON ci.d01 = a.e05
    JOIN cnt
        ON cnt.c01 = ci.d03
),
daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        cg.customer_name,
        cg.city_name,
        cg.country_name,
        DATE(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        MIN(p.p06) AS first_operation_ts,
        MAX(p.p06) AS last_operation_ts,
        MAX(CAST(p.p05 AS REAL)) AS max_single_payment
    FROM pay AS p
    JOIN stf AS s
        ON s.o01 = p.p03
    JOIN customer_geo AS cg
        ON cg.customer_id = p.p02
    GROUP BY
        p.p02,
        cg.customer_name,
        cg.city_name,
        cg.country_name,
        DATE(p.p06)
),
with_personal_prev AS (
    SELECT
        dp.*,
        (
            SELECT AVG(CAST(dp2.day_amount AS REAL))
            FROM daily_payments AS dp2
            WHERE dp2.customer_id = dp.customer_id
              AND dp2.payment_date >= DATE(dp.payment_date, '-30 days')
              AND dp2.payment_date < dp.payment_date
        ) AS avg_daily_amount_prev_30
    FROM daily_payments AS dp
),
country_daily_rank AS (
    SELECT
        wpp.*,
        RANK() OVER (
            PARTITION BY wpp.country_name, wpp.payment_date
            ORDER BY wpp.day_amount
        ) AS day_amount_rank_in_country_day,
        COUNT(*) OVER (
            PARTITION BY wpp.country_name, wpp.payment_date
        ) AS day_amount_count_in_country_day
    FROM with_personal_prev AS wpp
),
country_p95_by_day AS (
    SELECT
        country_name,
        payment_date,
        MAX(CASE WHEN day_amount_rank_in_country_day >= (0.95 * (day_amount_count_in_country_day - 1) + 1)
                 THEN day_amount END) AS p95_day_amount
    FROM country_daily_rank
    GROUP BY country_name, payment_date
),
scored AS (
    SELECT
        cdr.*,
        cp.p95_day_amount,
        (cdr.day_amount - cdr.avg_daily_amount_prev_30) AS deviation_from_personal_avg,
        CASE
            WHEN cdr.avg_daily_amount_prev_30 > 0
            THEN (cdr.day_amount / cdr.avg_daily_amount_prev_30)
        END AS personal_ratio,
        CASE
            WHEN cp.p95_day_amount > 0
            THEN (cdr.day_amount / cp.p95_day_amount)
        END AS country_ratio_vs_p95
    FROM with_personal_prev AS cdr
    JOIN country_p95_by_day AS cp
      ON cp.country_name = cdr.country_name
     AND cp.payment_date = cdr.payment_date
)
SELECT
    s.customer_id,
    s.customer_name,
    s.city_name,
    s.country_name,
    s.payment_date,
    s.payment_count,
    ROUND(s.day_amount, 2) AS day_amount,
    s.staff_count,
    s.store_count,
    s.first_operation_ts,
    s.last_operation_ts,
    ROUND(s.max_single_payment, 2) AS max_single_payment,
    RANK() OVER (
        PARTITION BY s.country_name
        ORDER BY (s.day_amount - s.avg_daily_amount_prev_30) DESC, s.day_amount DESC, s.customer_id
    ) AS suspicious_rank_in_country
FROM scored AS s
WHERE s.avg_daily_amount_prev_30 IS NOT NULL
  AND s.staff_count >= 2
  AND s.payment_count >= 3
  AND s.day_amount > 3.0 * s.avg_daily_amount_prev_30
  AND s.day_amount > s.p95_day_amount
ORDER BY
    s.country_name,
    suspicious_rank_in_country,
    s.payment_date,
    s.customer_id;