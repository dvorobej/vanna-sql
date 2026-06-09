WITH payment_enriched AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        p.p04 AS rental_id,
        p.p05 AS payment_amount,
        date(p.p06) AS payment_date,
        c.h03 || ' ' || c.h04 AS customer_name,
        co.c02 AS country_name,
        ci.d02 AS city_name
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ci
        ON ci.d01 = a.e05
    JOIN cnt AS co
        ON co.c01 = ci.d03
),
daily_customer AS (
    SELECT
        pe.customer_id,
        MAX(pe.customer_name) AS customer_name,
        MAX(pe.country_name) AS country_name,
        MAX(pe.city_name) AS city_name,
        pe.payment_date,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT pe.staff_id) AS distinct_staff_count,
        SUM(pe.payment_amount) AS day_total_amount
    FROM payment_enriched AS pe
    GROUP BY
        pe.customer_id,
        pe.payment_date
),
daily_with_avg AS (
    SELECT
        dc.*,
        (
            SELECT AVG(dc2.day_total_amount)
            FROM daily_customer AS dc2
            WHERE dc2.customer_id = dc.customer_id
              AND dc2.payment_date >= date(dc.payment_date, '-30 day')
              AND dc2.payment_date < dc.payment_date
        ) AS avg_daily_amount_prev_30
    FROM daily_customer AS dc
),
suspicious_days AS (
    SELECT
        d.*,
        (d.day_total_amount / NULLIF(d.avg_daily_amount_prev_30, 0)) AS exceed_coef
    FROM daily_with_avg AS d
    WHERE d.avg_daily_amount_prev_30 IS NOT NULL
      AND d.avg_daily_amount_prev_30 > 0
      AND d.day_total_amount >= 3 * d.avg_daily_amount_prev_30
      AND d.payment_count >= 3
      AND (d.distinct_staff_count >= 2)
),
ranked AS (
    SELECT
        sd.*,
        RANK() OVER (
            PARTITION BY sd.customer_id
            ORDER BY sd.day_total_amount DESC, sd.payment_date ASC
        ) AS customer_day_rank
    FROM suspicious_days AS sd
)
SELECT
    customer_id,
    customer_name,
    country_name,
    city_name,
    payment_date AS suspicious_date,
    payment_count,
    ROUND(day_total_amount, 2) AS total_amount,
    ROUND(avg_daily_amount_prev_30, 2) AS avg_daily_amount_prev_30,
    ROUND(exceed_coef, 4) AS exceed_coef,
    customer_day_rank
FROM ranked
ORDER BY
    country_name,
    city_name,
    customer_id,
    customer_day_rank,
    suspicious_date;