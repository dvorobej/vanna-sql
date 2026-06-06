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
payment_detail AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        date(p.p06) AS payment_day,
        CAST(p.p05 AS REAL) AS amount,
        p.p03 AS staff_id,
        stf.o07 AS store_id,
        p.p04 AS rental_id,
        flm.i02 AS film_title
    FROM pay AS p
    JOIN stf AS stf
        ON stf.o01 = p.p03
    LEFT JOIN ren AS r
        ON r.q01 = p.p04
    LEFT JOIN inv AS inv
        ON inv.n01 = r.q03
    LEFT JOIN flm AS flm
        ON flm.i01 = inv.n02
),
daily_customer AS (
    SELECT
        customer_id,
        payment_day,
        SUM(amount) AS daily_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT staff_id) AS staff_count,
        COUNT(DISTINCT store_id) AS store_count
    FROM payment_detail
    GROUP BY customer_id, payment_day
),
daily_country AS (
    SELECT
        cg.country_id,
        dc.payment_day,
        AVG(dc.daily_amount) AS country_avg_daily_amount
    FROM daily_customer AS dc
    JOIN customer_geo AS cg
        ON cg.customer_id = dc.customer_id
    GROUP BY cg.country_id, dc.payment_day
),
customer_history AS (
    SELECT
        dc.*,
        cg.country_id,
        cg.country_name,
        cg.city_name,
        AVG(dc.daily_amount) OVER (
            PARTITION BY dc.customer_id
            ORDER BY dc.payment_day
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS prev_30d_avg_daily_amount,
        COUNT(*) OVER (
            PARTITION BY dc.customer_id
            ORDER BY dc.payment_day
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS prev_30d_day_count
    FROM daily_customer AS dc
    JOIN customer_geo AS cg
        ON cg.customer_id = dc.customer_id
),
suspicious_days AS (
    SELECT
        ch.customer_id,
        ch.customer_name,
        ch.country_id,
        ch.country_name,
        ch.city_name,
        ch.payment_day,
        ch.daily_amount,
        ch.payment_count,
        ch.staff_count,
        ch.store_count,
        ch.prev_30d_avg_daily_amount,
        dcountry.country_avg_daily_amount,
        MAX(
            ch.daily_amount / NULLIF(ch.prev_30d_avg_daily_amount, 0),
            ch.daily_amount / NULLIF(dcountry.country_avg_daily_amount, 0)
        ) AS deviation_score
    FROM customer_history AS ch
    JOIN daily_country AS dcountry
        ON dcountry.country_id = ch.country_id
       AND dcountry.payment_day = ch.payment_day
    WHERE ch.prev_30d_day_count = 30
      AND ch.prev_30d_avg_daily_amount > 0
      AND dcountry.country_avg_daily_amount > 0
      AND ch.daily_amount >= 3.0 * ch.prev_30d_avg_daily_amount
      AND ch.daily_amount > dcountry.country_avg_daily_amount
      AND ch.payment_count >= 3
      AND (ch.staff_count > 1 OR ch.store_count > 1)
)
SELECT
    sd.customer_id,
    sd.customer_name,
    sd.country_name,
    sd.city_name,
    sd.payment_day AS anomaly_date,
    sd.payment_count,
    ROUND(sd.daily_amount, 2) AS daily_amount,
    ROUND(sd.prev_30d_avg_daily_amount, 2) AS prev_30d_avg_daily_amount,
    ROUND(sd.country_avg_daily_amount, 2) AS country_avg_daily_amount,
    ROUND(sd.daily_amount - sd.prev_30d_avg_daily_amount, 2) AS deviation_from_personal_avg,
    ROUND(sd.daily_amount - sd.country_avg_daily_amount, 2) AS deviation_from_country_avg,
    GROUP_CONCAT(DISTINCT pd.film_title, ', ') AS rented_film_titles,
    RANK() OVER (
        PARTITION BY sd.country_id
        ORDER BY sd.deviation_score DESC, sd.daily_amount DESC
    ) AS country_suspicion_rank
FROM suspicious_days AS sd
LEFT JOIN payment_detail AS pd
    ON pd.customer_id = sd.customer_id
   AND pd.payment_day = sd.payment_day
GROUP BY
    sd.customer_id,
    sd.customer_name,
    sd.country_name,
    sd.city_name,
    sd.payment_day,
    sd.payment_count,
    sd.daily_amount,
    sd.prev_30d_avg_daily_amount,
    sd.country_avg_daily_amount,
    sd.deviation_score,
    sd.country_id
ORDER BY
    country_suspicion_rank,
    sd.country_name,
    sd.payment_day,
    sd.customer_id;