WITH payment_enriched AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        cu.h03 || ' ' || cu.h04 AS customer_name,
        CASE
            WHEN TRIM(CAST(cu.h07 AS TEXT)) IN ('1', 'Y', 'y', 'T', 't') THEN 1
            ELSE 0
        END AS is_active,
        cnt.c01 AS country_id,
        cnt.c02 AS country,
        cty.d02 AS city,
        DATE(p.p06) AS payment_day,
        CAST(p.p05 AS REAL) AS amount,
        p.p03 AS staff_id,
        stf.o07 AS store_id,
        flm.i02 AS film_title
    FROM pay AS p
    JOIN cus AS cu
        ON cu.h01 = p.p02
    JOIN adr AS adr
        ON adr.e01 = cu.h06
    JOIN cty AS cty
        ON cty.d01 = adr.e05
    JOIN cnt AS cnt
        ON cnt.c01 = cty.d03
    JOIN stf AS stf
        ON stf.o01 = p.p03
    LEFT JOIN ren AS ren
        ON ren.q01 = p.p04
    LEFT JOIN inv AS inv
        ON inv.n01 = ren.q03
    LEFT JOIN flm AS flm
        ON flm.i01 = inv.n02
),
customer_day AS (
    SELECT
        customer_id,
        customer_name,
        is_active,
        country_id,
        country,
        city,
        payment_day,
        COUNT(payment_id) AS payment_count,
        SUM(amount) AS total_amount,
        COUNT(DISTINCT staff_id) AS staff_count,
        COUNT(DISTINCT store_id) AS store_count,
        GROUP_CONCAT(DISTINCT film_title) AS rented_films
    FROM payment_enriched
    GROUP BY
        customer_id,
        customer_name,
        is_active,
        country_id,
        country,
        city,
        payment_day
),
customer_day_windowed AS (
    SELECT
        cd.*,
        SUM(total_amount) OVER (
            PARTITION BY customer_id
            ORDER BY JULIANDAY(payment_day)
            RANGE BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) / 30.0 AS personal_30_day_avg
    FROM customer_day AS cd
),
country_day AS (
    SELECT
        country_id,
        payment_day,
        SUM(total_amount) AS country_total_amount
    FROM customer_day
    GROUP BY
        country_id,
        payment_day
),
country_day_windowed AS (
    SELECT
        country_id,
        payment_day,
        SUM(country_total_amount) OVER (
            PARTITION BY country_id
            ORDER BY JULIANDAY(payment_day)
            RANGE BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) / 30.0 AS country_30_day_daily_avg
    FROM country_day
),
scored AS (
    SELECT
        cdw.customer_id,
        cdw.customer_name,
        cdw.country,
        cdw.city,
        cdw.payment_day,
        cdw.payment_count,
        cdw.total_amount,
        cdw.staff_count,
        cdw.store_count,
        cdw.rented_films,
        cdw.personal_30_day_avg,
        ctw.country_30_day_daily_avg
    FROM customer_day_windowed AS cdw
    JOIN country_day_windowed AS ctw
        ON ctw.country_id = cdw.country_id
       AND ctw.payment_day = cdw.payment_day
    WHERE cdw.is_active = 1
)
SELECT
    customer_id,
    customer_name,
    country,
    city,
    payment_day AS suspicious_activity_date,
    payment_count,
    ROUND(total_amount, 2) AS total_amount,
    ROUND(total_amount - personal_30_day_avg, 2) AS deviation_from_personal_30_day_avg,
    ROUND(total_amount - country_30_day_daily_avg, 2) AS deviation_from_country_daily_avg,
    COALESCE(rented_films, '') AS rented_films
FROM scored
WHERE payment_count >= 3
  AND (staff_count >= 2 OR store_count >= 2)
  AND personal_30_day_avg > 0
  AND country_30_day_daily_avg > 0
  AND total_amount >= personal_30_day_avg * 3
  AND total_amount > country_30_day_daily_avg
ORDER BY
    suspicious_activity_date,
    deviation_from_personal_30_day_avg DESC,
    customer_id;