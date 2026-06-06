WITH payment_detail AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        stf.o07 AS store_id,
        DATE(p.p06) AS payment_day,
        CAST(p.p05 AS REAL) AS amount,
        flm.i02 AS film_title
    FROM pay AS p
    JOIN stf
        ON stf.o01 = p.p03
    LEFT JOIN ren
        ON ren.q01 = p.p04
    LEFT JOIN inv
        ON inv.n01 = ren.q03
    LEFT JOIN flm
        ON flm.i01 = inv.n02
),
daily_customer AS (
    SELECT
        pd.customer_id,
        pd.payment_day,
        COUNT(*) AS payment_count,
        SUM(pd.amount) AS total_amount,
        COUNT(DISTINCT pd.staff_id) AS distinct_staff_count,
        COUNT(DISTINCT pd.store_id) AS distinct_store_count,
        GROUP_CONCAT(DISTINCT pd.film_title) AS rented_film_titles
    FROM payment_detail AS pd
    GROUP BY
        pd.customer_id,
        pd.payment_day
),
customer_geo AS (
    SELECT
        cus.h01 AS customer_id,
        cus.h03 || ' ' || cus.h04 AS customer_name,
        cus.h05 AS email,
        cty.d02 AS city_name,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name
    FROM cus
    JOIN adr
        ON adr.e01 = cus.h06
    JOIN cty
        ON cty.d01 = adr.e05
    JOIN cnt
        ON cnt.c01 = cty.d03
    WHERE cus.h07 = 'Y'
),
daily_with_history AS (
    SELECT
        dc.customer_id,
        dc.payment_day,
        dc.payment_count,
        dc.total_amount,
        dc.distinct_staff_count,
        dc.distinct_store_count,
        dc.rented_film_titles,
        (
            SELECT SUM(prev.total_amount) / 30.0
            FROM daily_customer AS prev
            WHERE prev.customer_id = dc.customer_id
              AND prev.payment_day >= DATE(dc.payment_day, '-30 day')
              AND prev.payment_day < dc.payment_day
        ) AS customer_avg_30d_amount
    FROM daily_customer AS dc
),
daily_with_country AS (
    SELECT
        dwh.*,
        cg.customer_name,
        cg.email,
        cg.city_name,
        cg.country_id,
        cg.country_name,
        AVG(dwh.total_amount) OVER (
            PARTITION BY cg.country_id, dwh.payment_day
        ) AS country_daily_avg_amount
    FROM daily_with_history AS dwh
    JOIN customer_geo AS cg
        ON cg.customer_id = dwh.customer_id
)
SELECT
    customer_id,
    customer_name,
    email,
    country_name,
    city_name,
    payment_day AS anomaly_date,
    payment_count,
    ROUND(total_amount, 2) AS total_amount,
    distinct_staff_count,
    distinct_store_count,
    ROUND(customer_avg_30d_amount, 2) AS customer_avg_30d_amount,
    ROUND(total_amount / NULLIF(customer_avg_30d_amount, 0), 2) AS ratio_to_customer_30d_avg,
    ROUND(country_daily_avg_amount, 2) AS country_daily_avg_amount,
    ROUND(total_amount / NULLIF(country_daily_avg_amount, 0), 2) AS ratio_to_country_daily_avg,
    rented_film_titles
FROM daily_with_country
WHERE customer_avg_30d_amount > 0
  AND country_daily_avg_amount > 0
  AND total_amount >= 3.0 * customer_avg_30d_amount
  AND total_amount > country_daily_avg_amount
  AND payment_count >= 3
  AND (
      distinct_staff_count >= 2
      OR distinct_store_count >= 2
  )
ORDER BY
    ratio_to_customer_30d_avg DESC,
    ratio_to_country_daily_avg DESC,
    total_amount DESC,
    anomaly_date,
    customer_id;