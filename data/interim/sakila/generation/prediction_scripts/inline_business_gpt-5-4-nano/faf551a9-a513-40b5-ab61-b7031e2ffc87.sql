WITH payment_base AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        p.p04 AS rental_id,
        DATE(p.p06) AS payment_day,
        CAST(p.p05 AS REAL) AS payment_amount,
        c.h03 AS customer_first_name,
        c.h04 AS customer_last_name,
        s.o07 AS store_id,
        co.c01 AS country_id,
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
    JOIN stf AS s
        ON s.o01 = p.p03
),
daily_customer_store AS (
    SELECT
        customer_id,
        customer_first_name,
        customer_last_name,
        country_id,
        country_name,
        city_name,
        store_id,
        payment_day,
        COUNT(*) AS payment_count,
        SUM(payment_amount) AS day_amount
    FROM payment_base
    GROUP BY
        customer_id,
        customer_first_name,
        customer_last_name,
        country_id,
        country_name,
        city_name,
        store_id,
        payment_day
),
daily_with_history AS (
    SELECT
        d.*,
        (
            SELECT AVG(dh.day_amount)
            FROM daily_customer_store AS dh
            WHERE dh.customer_id = d.customer_id
              AND dh.store_id = d.store_id
              AND dh.country_id = d.country_id
              AND dh.payment_day >= DATE(d.payment_day, '-29 days')
              AND dh.payment_day <= DATE(d.payment_day, '-1 day')
        ) AS avg_prev30d_day_amount
    FROM daily_customer_store AS d
),
flagged_windows AS (
    SELECT
        dwh.*,
        (dwh.day_amount - dwh.avg_prev30d_day_amount) AS deviation_from_avg,
        dwh.day_amount / NULLIF(dwh.avg_prev30d_day_amount, 0) AS exceed_ratio
    FROM daily_with_history AS dwh
    WHERE dwh.avg_prev30d_day_amount IS NOT NULL
      AND dwh.avg_prev30d_day_amount > 0
      AND dwh.day_amount >= 3.0 * dwh.avg_prev30d_day_amount
),
country_exception_ranking AS (
    SELECT
        fw.*,
        RANK() OVER (
            PARTITION BY fw.country_id, fw.payment_day, fw.store_id
            ORDER BY fw.day_amount DESC
        ) AS spike_rank_in_country
    FROM flagged_windows AS fw
),
country_group_percentile AS (
    SELECT
        country_id,
        payment_day,
        store_id,
        COUNT(*) AS n,
        CAST((95.0 * COUNT(*) + 5) / 100 AS INTEGER) AS p95_row_num
    FROM country_exception_ranking
    GROUP BY country_id, payment_day, store_id
),
country_p95 AS (
    SELECT
        cer.country_id,
        cer.payment_day,
        cer.store_id,
        MAX(cer.day_amount) AS p95_day_amount
    FROM (
        SELECT
            cer.*,
            ROW_NUMBER() OVER (
                PARTITION BY cer.country_id, cer.payment_day, cer.store_id
                ORDER BY cer.day_amount ASC, cer.customer_id ASC
            ) AS asc_row_num
        FROM country_exception_ranking AS cer
    ) AS cer
    JOIN country_group_percentile AS cgp
      ON cgp.country_id = cer.country_id
     AND cgp.payment_day = cer.payment_day
     AND cgp.store_id = cer.store_id
    WHERE cer.asc_row_num = cgp.p95_row_num
    GROUP BY cer.country_id, cer.payment_day, cer.store_id
)
SELECT
    cer.payment_day AS spike_date,
    cer.customer_first_name,
    cer.customer_last_name,
    cer.country_name,
    cer.city_name,
    cer.store_id,
    cer.payment_count,
    ROUND(cer.day_amount, 2) AS day_sum,
    ROUND(cer.avg_prev30d_day_amount, 2) AS avg_prev30d_day_amount,
    ROUND(cer.deviation_from_avg, 2) AS deviation_from_avg,
    cer.spike_rank_in_country
FROM country_exception_ranking AS cer
JOIN country_p95 AS p95
  ON p95.country_id = cer.country_id
 AND p95.payment_day = cer.payment_day
 AND p95.store_id = cer.store_id
WHERE cer.day_amount > p95.p95_day_amount
ORDER BY
    cer.country_name,
    cer.payment_day,
    cer.store_id,
    cer.spike_rank_in_country,
    cer.customer_id;