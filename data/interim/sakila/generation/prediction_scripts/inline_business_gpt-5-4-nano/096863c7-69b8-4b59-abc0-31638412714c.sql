WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        a.e05 AS city_id,
        city.d02 AS city_name,
        cnt.c02 AS country_id_name,
        cnt.c01 AS country_id
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS city ON city.d01 = a.e05
    JOIN cnt AS cnt ON cnt.c01 = city.d03
),
daily_customer_payments AS (
    SELECT
        cg.customer_id,
        cg.customer_name,
        cg.city_name,
        cg.country_id,
        cg.country_id_name,
        date(p.p06) AS payment_day,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN customer_geo AS cg ON cg.customer_id = p.p02
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY
        cg.customer_id, cg.customer_name, cg.city_name,
        cg.country_id, cg.country_id_name, date(p.p06)
),
daily_with_history AS (
    SELECT
        d.*,
        (
            SELECT AVG(dh.day_amount)
            FROM daily_customer_payments AS dh
            WHERE dh.customer_id = d.customer_id
              AND dh.payment_day >= date(d.payment_day, '-30 days')
              AND dh.payment_day < d.payment_day
        ) AS personal_avg_daily_amount_30d
    FROM daily_customer_payments AS d
),
daily_with_country_avg AS (
    SELECT
        dwh.*,
        (
            SELECT AVG(dc.day_amount)
            FROM daily_customer_payments AS dc
            WHERE dc.country_id = dwh.country_id
              AND dc.payment_day = dwh.payment_day
        ) AS country_avg_daily_amount
    FROM daily_with_history AS dwh
),
ranked_country AS (
    SELECT
        d.*,
        RANK() OVER (
            PARTITION BY d.country_id
            ORDER BY d.day_amount DESC
        ) AS suspicious_sum_rank_in_country
    FROM daily_with_country_avg AS d
)
SELECT
    rc.customer_id,
    rc.customer_name,
    rc.city_name,
    rc.country_id_name AS country,
    rc.payment_day AS operation_date,
    rc.payment_count,
    ROUND(rc.day_amount, 2) AS day_amount,
    ROUND(rc.personal_avg_daily_amount_30d, 2) AS personal_avg_daily_amount_30d,
    ROUND(rc.country_avg_daily_amount, 2) AS country_avg_daily_amount,
    ROUND(rc.day_amount - rc.personal_avg_daily_amount_30d, 2) AS deviation_from_personal_avg,
    ROUND(rc.day_amount - rc.country_avg_daily_amount, 2) AS deviation_from_country_avg,
    rc.staff_count,
    rc.store_count,
    rc.suspicious_sum_rank_in_country
FROM ranked_country AS rc
WHERE rc.personal_avg_daily_amount_30d IS NOT NULL
  AND rc.country_avg_daily_amount IS NOT NULL
  AND rc.payment_count >= 1
  AND rc.day_amount >= 3 * rc.personal_avg_daily_amount_30d
  AND rc.day_amount > rc.country_avg_daily_amount
ORDER BY
    rc.country_id_name,
    rc.suspicious_sum_rank_in_country,
    rc.day_amount DESC,
    rc.customer_id,
    rc.payment_day;