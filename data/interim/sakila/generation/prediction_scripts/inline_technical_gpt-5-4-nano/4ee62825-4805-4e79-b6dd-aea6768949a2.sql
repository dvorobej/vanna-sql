WITH daily AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_day,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS total_amount,
        MIN(p.p06) AS min_payment_ts,
        MAX(p.p06) AS max_payment_ts,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        MAX(CAST(p.p05 AS REAL)) AS max_payment_amount
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
    JOIN sto AS st
        ON st.j01 = s.o07
       AND st.j01 = s.o07
    WHERE c.h07 = 'Y'
    GROUP BY
        p.p02,
        DATE(p.p06)
),
with_personal_avg AS (
    SELECT
        d.*,
        (
            SELECT AVG(d2.total_amount)
            FROM daily AS d2
            WHERE d2.customer_id = d.customer_id
              AND d2.payment_day >= DATE(d.payment_day, '-30 days')
              AND d2.payment_day < d.payment_day
        ) AS avg_prev_30d
    FROM daily AS d
),
country_daily_stats AS (
    SELECT
        ci.c01 AS country_id,
        ci.d02 AS country_city, -- not used in ranking, but kept for clarity
        d2.payment_day,
        d2.total_amount
    FROM daily AS d2
    JOIN cus AS c
        ON c.h01 = d2.customer_id
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ci
        ON ci.d01 = a.e05
    -- need country id: cnt.c01
),
country_p95 AS (
    SELECT
        c.country_id,
        c.p95_amount
    FROM (
        SELECT
            co.c01 AS country_id,
            d.total_amount,
            NTILE(100) OVER (
                PARTITION BY co.c01
                ORDER BY d.total_amount
            ) AS tile_100
        FROM daily AS d
        JOIN cus AS c2
            ON c2.h01 = d.customer_id
        JOIN adr AS a
            ON a.e01 = c2.h06
        JOIN cty AS ci
            ON ci.d01 = a.e05
        JOIN cnt AS co
            ON co.c01 = ci.d03
    ) AS c
    CROSS JOIN (
        SELECT 95 AS dummy
    ) AS x
    WHERE c.tile_100 = 100
    GROUP BY c.country_id
    HAVING 1=1
),
filtered_days AS (
    SELECT
        wp.customer_id,
        wp.payment_day,
        wp.payment_count,
        wp.total_amount,
        wp.min_payment_ts,
        wp.max_payment_ts,
        wp.staff_count,
        wp.store_count,
        wp.max_payment_amount,
        wp.avg_prev_30d,
        -- compute ratio over historical personal avg
        CASE
            WHEN wp.avg_prev_30d IS NOT NULL AND wp.avg_prev_30d > 0
            THEN wp.total_amount / wp.avg_prev_30d
            ELSE NULL
        END AS exceed_ratio_personal
    FROM with_personal_avg AS wp
    WHERE wp.avg_prev_30d IS NOT NULL
      AND wp.avg_prev_30d > 0
      AND wp.payment_count >= 3
      AND wp.staff_count >= 2
      AND wp.total_amount >= 3.0 * wp.avg_prev_30d
),
final_rank AS (
    SELECT
        fd.*,
        co.c01 AS country_id,
        ci.d02 AS city_name,
        co.c02 AS country_name,
        RANK() OVER (
            PARTITION BY co.c01
            ORDER BY
                fd.total_amount / NULLIF(fd.avg_prev_30d, 0) DESC,
                fd.total_amount DESC,
                fd.customer_id
        ) AS suspicion_rank_in_country
    FROM filtered_days AS fd
    JOIN cus AS c
        ON c.h01 = fd.customer_id
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ci
        ON ci.d01 = a.e05
    JOIN cnt AS co
        ON co.c01 = ci.d03
)
SELECT
    fr.customer_id AS h01,
    fr.city_name AS d02,
    fr.country_name AS c02,
    fr.payment_day AS p06,
    fr.payment_count AS payment_count,
    ROUND(fr.total_amount, 2) AS total_amount,
    fr.staff_count AS staff_count,
    fr.store_count AS store_count,
    fr.min_payment_ts AS min_payment_ts_in_day,
    fr.max_payment_ts AS max_payment_ts_in_day,
    ROUND(fr.max_payment_amount, 2) AS max_payment_amount,
    fr.exceed_ratio_personal AS exceed_ratio_personal_avg30d,
    fr.suspicion_rank_in_country AS suspicion_rank_in_country
FROM final_rank AS fr
ORDER BY
    fr.country_name,
    fr.suspicion_rank_in_country,
    fr.payment_day,
    fr.customer_id;