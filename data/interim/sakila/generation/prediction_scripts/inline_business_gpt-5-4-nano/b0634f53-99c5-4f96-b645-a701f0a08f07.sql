WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        co.c02 AS customer_country
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS city
        ON city.d01 = a.e05
    JOIN cnt AS co
        ON co.c01 = city.d03
),
daily AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_day,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_payment_sum,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT s.o07) AS distinct_store_count,
        GROUP_CONCAT(DISTINCT s.o07) AS store_ids,
        GROUP_CONCAT(DISTINCT st_country.c02) AS store_countries_concat
    FROM pay AS p
    JOIN stf AS s
        ON s.o01 = p.p03
    JOIN adr AS sa
        ON sa.e01 = s.o04
    JOIN cty AS scity
        ON scity.d01 = sa.e05
    JOIN cnt AS st_country
        ON st_country.c01 = scity.d03
    GROUP BY
        p.p02,
        DATE(p.p06)
),
daily_with_history AS (
    SELECT
        d.*,
        cg.customer_country,
        (
            SELECT AVG(CAST(dh.day_payment_sum AS REAL))
            FROM daily AS dh
            WHERE dh.customer_id = d.customer_id
              AND dh.payment_day >= DATE(d.payment_day, '-30 days')
              AND dh.payment_day <  d.payment_day
        ) AS avg_daily_prev_30
    FROM daily AS d
    JOIN customer_geo AS cg
        ON cg.customer_id = d.customer_id
),
flagged AS (
    SELECT
        dwh.*,
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM pay AS p
                JOIN stf AS s ON s.o01 = p.p03
                JOIN adr AS sa ON sa.e01 = s.o04
                JOIN cty AS scity ON scity.d01 = sa.e05
                JOIN cnt AS st_country ON st_country.c01 = scity.d03
                WHERE p.p02 = dwh.customer_id
                  AND DATE(p.p06) = dwh.payment_day
                  AND st_country.c02 <> dwh.customer_country
            ) THEN 1 ELSE 0
        END AS has_off_country_store_payment
    FROM daily_with_history AS dwh
)
SELECT
    cg.customer_id,
    cg.customer_name,
    f.payment_day AS suspicious_date,
    f.customer_country,
    f.payment_count,
    ROUND(f.day_payment_sum, 2) AS day_payment_sum,
    ROUND(f.avg_daily_prev_30, 2) AS avg_daily_prev_30,
    f.distinct_staff_count,
    f.distinct_store_count,
    f.store_ids,
    f.store_countries_concat,
    RANK() OVER (
        PARTITION BY f.customer_country
        ORDER BY (f.day_payment_sum / NULLIF(f.avg_daily_prev_30, 0)) DESC,
                 f.day_payment_sum DESC,
                 f.payment_day
    ) AS suspicion_rank_in_country
FROM flagged AS f
JOIN customer_geo AS cg
    ON cg.customer_id = f.customer_id
WHERE f.avg_daily_prev_30 IS NOT NULL
  AND f.avg_daily_prev_30 > 0
  AND f.payment_count >= 3
  AND f.day_payment_sum >= 2.0 * f.avg_daily_prev_30
  AND f.has_off_country_store_payment = 1
ORDER BY
    f.customer_country,
    suspicion_rank_in_country,
    f.day_payment_sum DESC,
    f.payment_day;