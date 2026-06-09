WITH payment_base AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_day,
        p.p05 AS payment_amount,
        p.p03 AS staff_id,
        s.o07 AS store_id,
        a.e05 AS city_id,
        city.d03 AS country_id_customer
    FROM pay p
    JOIN cus c
        ON c.h01 = p.p02
    JOIN adr a
        ON a.e01 = c.h06
    JOIN cty city
        ON city.d01 = a.e05
    JOIN stf s
        ON s.o01 = p.p03
),
daily AS (
    SELECT
        pb.customer_id,
        pb.payment_day,
        COUNT(*) AS payment_count,
        SUM(pb.payment_amount) AS day_amount,
        COUNT(DISTINCT pb.staff_id) AS distinct_staff_count,
        COUNT(DISTINCT pb.store_id) AS distinct_store_count,
        COUNT(DISTINCT s_city.d03) AS distinct_store_countries_count,
        GROUP_CONCAT(DISTINCT s_city.d03) AS store_countries_ids
    FROM payment_base pb
    JOIN sto sto
        ON sto.j01 = pb.store_id
    JOIN adr s_adr
        ON s_adr.e01 = sto.j03
    JOIN cty s_city
        ON s_city.d01 = s_adr.e05
    GROUP BY
        pb.customer_id,
        pb.payment_day
),
daily_with_history AS (
    SELECT
        d.*,
        (
            SELECT AVG(d2.day_amount)
            FROM daily d2
            WHERE d2.customer_id = d.customer_id
              AND d2.payment_day >= date(d.payment_day, '-30 day')
              AND d2.payment_day < d.payment_day
        ) AS avg_daily_amount_prev_30d
    FROM daily d
),
customer_country_city AS (
    SELECT
        c.h01 AS customer_id,
        co.c02 AS customer_country,
        ci.d02 AS customer_city
    FROM cus c
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ci ON ci.d01 = a.e05
    JOIN cnt co ON co.c01 = ci.d03
)
SELECT
    cc.customer_id,
    cc.customer_country,
    cc.customer_city,
    dwh.payment_day AS suspicious_date,
    dwh.payment_count,
    ROUND(dwh.day_amount, 2) AS day_amount,
    ROUND(dwh.avg_daily_amount_prev_30d, 2) AS avg_daily_amount_prev_30d,
    ROUND(dwh.day_amount / NULLIF(dwh.avg_daily_amount_prev_30d, 0), 2) AS exceed_ratio,
    dwh.distinct_staff_count,
    dwh.distinct_store_count,
    dwh.store_countries_ids AS store_countries_ids,
    RANK() OVER (
        PARTITION BY cc.customer_id
        ORDER BY (dwh.day_amount / NULLIF(dwh.avg_daily_amount_prev_30d, 0)) DESC,
                 dwh.day_amount DESC,
                 dwh.payment_day DESC
    ) AS suspicious_rank_within_customer
FROM daily_with_history dwh
JOIN customer_country_city cc
    ON cc.customer_id = dwh.customer_id
WHERE dwh.payment_count >= 3
  AND dwh.avg_daily_amount_prev_30d IS NOT NULL
  AND dwh.avg_daily_amount_prev_30d > 0
  AND dwh.day_amount >= 2.0 * dwh.avg_daily_amount_prev_30d
  AND dwh.distinct_store_countries_count >= 2
ORDER BY
    cc.customer_country,
    cc.customer_city,
    exceed_ratio DESC,
    suspicious_date;