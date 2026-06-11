WITH payment_enriched AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p03 AS staff_id,
        s.o07 AS staff_store_id,
        c.h06 AS customer_address_id,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        cty.d02 AS city_name
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty
        ON cty.d01 = a.e05
    JOIN cnt
        ON cnt.c01 = cty.d03
    JOIN stf AS s
        ON s.o01 = p.p03
    WHERE p.p06 IS NOT NULL
),
daily_customer AS (
    SELECT
        customer_id,
        country_id,
        country_name,
        city_name,
        payment_date,
        COUNT(*) AS payment_count,
        SUM(payment_amount) AS day_total_amount,
        COUNT(DISTINCT staff_id) AS distinct_staff_count,
        COUNT(DISTINCT staff_store_id) AS distinct_store_count
    FROM payment_enriched
    GROUP BY
        customer_id,
        country_id,
        country_name,
        city_name,
        payment_date
),
daily_with_history AS (
    SELECT
        dc.*,
        (
            SELECT AVG(dc_prev.day_total_amount)
            FROM daily_customer AS dc_prev
            WHERE dc_prev.customer_id = dc.customer_id
              AND dc_prev.payment_date >= date(dc.payment_date, '-30 days')
              AND dc_prev.payment_date < dc.payment_date
        ) AS avg_prev_30d
    FROM daily_customer AS dc
),
suspicious_days AS (
    SELECT
        dwh.*,
        (dwh.day_total_amount / NULLIF(dwh.avg_prev_30d, 0.0)) AS exceed_multiplier
    FROM daily_with_history AS dwh
    WHERE dwh.avg_prev_30d IS NOT NULL
      AND dwh.avg_prev_30d > 0
      AND dwh.payment_count >= 3
      AND dwh.day_total_amount >= 3.0 * dwh.avg_prev_30d
      AND (dwh.distinct_staff_count >= 2 OR dwh.distinct_store_count >= 2)
),
ranked_days AS (
    SELECT
        sd.*,
        RANK() OVER (
            PARTITION BY sd.customer_id
            ORDER BY sd.day_total_amount DESC, sd.payment_date
        ) AS day_rank_within_customer
    FROM suspicious_days AS sd
)
SELECT
    customer_id,
    country_name,
    city_name,
    payment_date,
    payment_count,
    ROUND(day_total_amount, 2) AS day_total_amount,
    ROUND(avg_prev_30d, 2) AS avg_prev_30d,
    ROUND(exceed_multiplier, 3) AS exceed_multiplier,
    day_rank_within_customer
FROM ranked_days
ORDER BY
    customer_id,
    day_rank_within_customer,
    payment_date;