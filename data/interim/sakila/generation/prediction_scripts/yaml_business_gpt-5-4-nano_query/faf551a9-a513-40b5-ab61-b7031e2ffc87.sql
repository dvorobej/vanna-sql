WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        city.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS city ON city.d01 = a.e05
    JOIN cnt AS cnt ON cnt.c01 = city.d03
),
daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        cg.first_name,
        cg.last_name,
        cg.country_id,
        cg.country_name,
        cg.city_name,
        DATE(p.p06) AS payment_day,
        p.p03 AS staff_id,
        i.n03 AS store_id,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(*) AS payment_count
    FROM pay AS p
    JOIN customer_geo AS cg ON cg.customer_id = p.p02
    JOIN ren r ON r.q01 = p.p04
    JOIN inv i ON i.n01 = r.q03
    GROUP BY
        p.p02,
        cg.first_name,
        cg.last_name,
        cg.country_id,
        cg.country_name,
        cg.city_name,
        DATE(p.p06),
        p.p03,
        i.n03
),
daily_customer AS (
    SELECT
        customer_id,
        first_name,
        last_name,
        country_id,
        country_name,
        city_name,
        payment_day,
        SUM(day_amount) AS day_amount,
        SUM(payment_count) AS payment_count,
        GROUP_CONCAT(DISTINCT staff_id) AS staff_list,
        GROUP_CONCAT(DISTINCT store_id) AS store_list,
        COUNT(DISTINCT store_id) AS distinct_store_count,
        COUNT(DISTINCT staff_id) AS distinct_staff_count
    FROM daily_payments
    GROUP BY
        customer_id,
        first_name,
        last_name,
        country_id,
        country_name,
        city_name,
        payment_day
),
with_personal_avg AS (
    SELECT
        dc.*,
        (
            SELECT AVG(dc2.day_amount)
            FROM daily_customer AS dc2
            WHERE dc2.customer_id = dc.customer_id
              AND dc2.payment_day >= date(dc.payment_day, '-30 days')
              AND dc2.payment_day < dc.payment_day
        ) AS avg_daily_prev_30d
    FROM daily_customer AS dc
),
country_sorted AS (
    SELECT
        wc.country_id,
        wc.payment_day,
        wc.day_amount,
        ROW_NUMBER() OVER (
            PARTITION BY wc.country_id
            ORDER BY wc.day_amount
        ) AS rn_asc,
        COUNT(*) OVER (
            PARTITION BY wc.country_id
        ) AS cnt_days
    FROM with_personal_avg AS wc
    GROUP BY wc.country_id, wc.payment_day, wc.day_amount
),
country_p95 AS (
    SELECT
        country_id,
        MIN(day_amount) AS p95_day_amount
    FROM country_sorted
    WHERE rn_asc >= CEIL(cnt_days * 0.95)
    GROUP BY country_id
),
filtered AS (
    SELECT
        wpa.*,
        c95.p95_day_amount,
        (wpa.day_amount - wpa.avg_daily_prev_30d) AS deviation_from_personal_avg
    FROM with_personal_avg AS wpa
    JOIN country_p95 AS c95 ON c95.country_id = wpa.country_id
    WHERE wpa.avg_daily_prev_30d IS NOT NULL
      AND wpa.avg_daily_prev_30d > 0
      AND wpa.day_amount >= 3.0 * wpa.avg_daily_prev_30d
      AND wpa.day_amount > c95.p95_day_amount
),
ranked AS (
    SELECT
        f.*,
        RANK() OVER (
            PARTITION BY f.country_id
            ORDER BY f.day_amount DESC, f.payment_day
        ) AS customer_surge_rank_in_country
    FROM filtered AS f
)
SELECT
    customer_id,
    first_name,
    last_name,
    country_name,
    city_name,
    store_list AS stores,
    payment_day AS surge_date,
    payment_count,
    ROUND(day_amount, 2) AS day_amount,
    ROUND(avg_daily_prev_30d, 2) AS avg_daily_prev_30d,
    ROUND(deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
    customer_surge_rank_in_country
FROM ranked
ORDER BY
    country_name,
    customer_surge_rank_in_country,
    surge_date,
    customer_id;