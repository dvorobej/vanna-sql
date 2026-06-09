WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        c.h06 AS customer_address_id,
        c.h01 AS customer_key,
        adr.dummy AS dummy_col,
        p.p04 AS rental_id,
        date(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_sum,
        MAX(CAST(p.p05 AS REAL)) AS max_payment
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    LEFT JOIN adr ON adr.e01 = c.h06
    WHERE p.p06 IS NOT NULL
    GROUP BY
        p.p02,
        c.h06,
        c.h01,
        date(p.p06),
        p.p04
),
daily_payments_fixed AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_sum,
        MAX(CAST(p.p05 AS REAL)) AS max_payment
    FROM pay AS p
    GROUP BY
        p.p02,
        date(p.p06)
),
daily_with_window AS (
    SELECT
        dp.customer_id,
        dp.payment_date,
        dp.payment_count,
        dp.day_sum,
        dp.max_payment,
        (
            SELECT AVG(CAST(d2.day_sum AS REAL))
            FROM daily_payments_fixed AS d2
            WHERE d2.customer_id = dp.customer_id
              AND d2.payment_date >= date(dp.payment_date, '-30 days')
              AND d2.payment_date < dp.payment_date
        ) AS avg_prev_30d
    FROM daily_payments_fixed AS dp
),
daily_geo AS (
    SELECT
        c.h01 AS customer_id,
        ci.d02 AS city,
        co.c02 AS country,
        co.c01 AS country_id
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
),
day_flm_flags AS (
    SELECT
        date(p.p06) AS payment_date,
        p.p02 AS customer_id,
        SUM(
            CASE
                WHEN COALESCE(CAST(fm.rating AS TEXT), '') IN ('R', 'NC-17') THEN 1
                ELSE 0
            END
        ) AS unrated_or_restricted_count,
        COUNT(*) AS total_count
    FROM pay AS p
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    JOIN flm AS fm ON fm.i01 = i.n02
    WHERE p.p06 IS NOT NULL
    GROUP BY
        date(p.p06),
        p.p02
)
SELECT
    dpw.customer_id,
    dg.city AS d02,
    dg.country AS c02,
    dpw.payment_date,
    dpw.payment_count,
    ROUND(dpw.day_sum, 2) AS day_sum,
    ROUND(dpw.max_payment, 2) AS max_payment,
    ROUND(
        1.0 * COALESCE(dff.unrated_or_restricted_count, 0) / NULLIF(dff.total_count, 0),
        4
    ) AS restricted_rating_payments_share,
    RANK() OVER (
        PARTITION BY dg.country_id, dpw.payment_date
        ORDER BY dpw.day_sum DESC
    ) AS day_rank_in_country
FROM daily_with_window AS dpw
JOIN daily_geo AS dg
    ON dg.customer_id = dpw.customer_id
JOIN day_flm_flags AS dff
    ON dff.customer_id = dpw.customer_id
   AND dff.payment_date = dpw.payment_date
WHERE dpw.payment_count >= 3
  AND dpw.avg_prev_30d IS NOT NULL
  AND dpw.avg_prev_30d > 0
  AND dpw.day_sum >= 3.0 * dpw.avg_prev_30d
ORDER BY
    dg.country,
    dpw.payment_date,
    dpw.day_sum DESC,
    dpw.customer_id;