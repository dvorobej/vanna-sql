WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        c.h05 AS email,
        city.d02 AS city_name,
        country.c02 AS country_name,
        country.c01 AS country_id
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS city
        ON city.d01 = a.e05
    JOIN cnt AS country
        ON country.c01 = city.d03
    WHERE c.h07 = 'Y'
),
payment_base AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        p.p04 AS rental_id,
        DATE(p.p06) AS payment_date,
        CAST(p.p05 AS REAL) AS amount,
        inv.n02 AS film_id,
        flm.i02 AS film_title,
        stf.o07 AS store_id
    FROM pay AS p
    LEFT JOIN ren AS r
        ON r.q01 = p.p04
    LEFT JOIN inv AS inv
        ON inv.n01 = r.q03
    LEFT JOIN flm AS flm
        ON flm.i01 = inv.n02
    LEFT JOIN stf AS stf
        ON stf.o01 = p.p03
),
daily_customer AS (
    SELECT
        customer_id,
        payment_date,
        COUNT(*) AS payment_count,
        SUM(amount) AS daily_amount,
        COUNT(DISTINCT staff_id) AS distinct_staff_count,
        COUNT(DISTINCT store_id) AS distinct_store_count
    FROM payment_base
    GROUP BY customer_id, payment_date
),
customer_hist AS (
    SELECT
        dc.*,
        AVG(daily_amount) OVER (
            PARTITION BY customer_id
            ORDER BY payment_date
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS prev_30d_avg_amount
    FROM daily_customer AS dc
),
country_daily AS (
    SELECT
        cg.country_id,
        pb.payment_date,
        AVG(SUM(pb.amount)) OVER (
            PARTITION BY cg.country_id
            ORDER BY pb.payment_date
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS country_prev_30d_avg_amount
    FROM payment_base AS pb
    JOIN customer_geo AS cg
        ON cg.customer_id = pb.customer_id
    GROUP BY cg.country_id, pb.payment_date
),
rental_titles AS (
    SELECT
        pb.customer_id,
        pb.payment_date,
        GROUP_CONCAT(DISTINCT pb.film_title) AS rented_film_titles
    FROM payment_base AS pb
    WHERE pb.film_title IS NOT NULL
    GROUP BY pb.customer_id, pb.payment_date
),
scored AS (
    SELECT
        cg.country_name,
        cg.city_name,
        ch.customer_id,
        cg.customer_name,
        ch.payment_date,
        ch.payment_count,
        ROUND(ch.daily_amount, 2) AS daily_amount,
        ROUND(ch.prev_30d_avg_amount, 2) AS prev_30d_avg_amount,
        ROUND(cd.country_prev_30d_avg_amount, 2) AS country_prev_30d_avg_amount,
        ch.distinct_staff_count,
        ch.distinct_store_count,
        ROUND(ch.daily_amount / NULLIF(ch.prev_30d_avg_amount, 0), 2) AS deviation_from_customer_avg,
        ROUND(ch.daily_amount / NULLIF(cd.country_prev_30d_avg_amount, 0), 2) AS deviation_from_country_avg,
        rt.rented_film_titles
    FROM customer_hist AS ch
    JOIN customer_geo AS cg
        ON cg.customer_id = ch.customer_id
    LEFT JOIN country_daily AS cd
        ON cd.country_id = cg.country_id
       AND cd.payment_date = ch.payment_date
    LEFT JOIN rental_titles AS rt
        ON rt.customer_id = ch.customer_id
       AND rt.payment_date = ch.payment_date
    WHERE ch.payment_count >= 3
      AND (ch.distinct_staff_count >= 3 OR ch.distinct_store_count >= 3)
)
SELECT
    country_name,
    city_name,
    customer_id,
    customer_name,
    payment_date,
    payment_count,
    daily_amount,
    prev_30d_avg_amount,
    country_prev_30d_avg_amount,
    deviation_from_customer_avg,
    deviation_from_country_avg,
    rented_film_titles
FROM scored
WHERE daily_amount >= 3.0 * prev_30d_avg_amount
  AND daily_amount >= 3.0 * country_prev_30d_avg_amount
ORDER BY
    daily_amount DESC,
    customer_id,
    payment_date;