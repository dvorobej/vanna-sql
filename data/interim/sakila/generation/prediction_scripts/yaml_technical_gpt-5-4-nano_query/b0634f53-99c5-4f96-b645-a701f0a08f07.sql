WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        cnt.c02 AS customer_country,
        ct.d02 AS customer_city,
        c.h02 AS customer_home_store_id
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt ON cnt.c01 = ct.d03
),
payment_days AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_day,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(*) AS payment_count
    FROM pay AS p
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 <  '2006-01-01'
    GROUP BY
        p.p02,
        date(p.p06)
),
payment_staff_store AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_day,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT s.o07) AS distinct_store_count,
        GROUP_CONCAT(DISTINCT str.c02) AS store_countries
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    JOIN adr AS a ON a.e01 = s.o07
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS str ON str.c01 = ct.d03
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 <  '2006-01-01'
    GROUP BY
        p.p02,
        date(p.p06)
),
payment_day_countries AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_day,
        MAX(CASE WHEN str.c02 <> cg.customer_country THEN 1 ELSE 0 END) AS has_foreign_store_country_payment
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN adr AS ca ON ca.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = ca.e05
    JOIN cnt AS cg_cnt ON cg_cnt.c01 = ct.d03
    JOIN stf AS s ON s.o01 = p.p03
    JOIN adr AS sa ON sa.e01 = s.o07
    JOIN cty AS sct ON sct.d01 = sa.e05
    JOIN cnt AS str ON str.c01 = sct.d03
    JOIN customer_geo AS cg ON cg.customer_id = p.p02
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 <  '2006-01-01'
    GROUP BY
        p.p02,
        date(p.p06)
),
scored AS (
    SELECT
        pd.customer_id,
        cg.customer_country,
        cg.customer_city,
        pd.payment_day,
        pd.payment_count,
        pd.day_amount,
        ROUND((
            SELECT AVG(CAST(p2.p05 AS REAL))
            FROM pay AS p2
            WHERE p2.p02 = pd.customer_id
              AND p2.p06 >= datetime(pd.payment_day, '-30 days')
              AND p2.p06 <  datetime(pd.payment_day, '-0 days')
        ), 2) AS avg_daily_amount_prev_30d,
        pss.distinct_staff_count,
        pss.distinct_store_count,
        pss.store_countries,
        pdc.has_foreign_store_country_payment
    FROM payment_days AS pd
    JOIN customer_geo AS cg
        ON cg.customer_id = pd.customer_id
    LEFT JOIN payment_staff_store AS pss
        ON pss.customer_id = pd.customer_id
       AND pss.payment_day = pd.payment_day
    LEFT JOIN payment_day_countries AS pdc
        ON pdc.customer_id = pd.customer_id
       AND pdc.payment_day = pd.payment_day
    WHERE pd.payment_count >= 3
      AND pdc.has_foreign_store_country_payment = 1
      AND (
        SELECT AVG(CAST(p2.p05 AS REAL))
        FROM pay AS p2
        WHERE p2.p02 = pd.customer_id
          AND p2.p06 >= datetime(pd.payment_day, '-30 days')
          AND p2.p06 <  datetime(pd.payment_day, '-0 days')
      ) > 0
)
SELECT
    s.customer_id,
    s.customer_country,
    s.customer_city,
    s.payment_day,
    s.payment_count,
    ROUND(s.day_amount, 2) AS day_amount,
    s.avg_daily_amount_prev_30d,
    ROUND((s.day_amount / NULLIF(s.avg_daily_amount_prev_30d, 0)), 2) AS exceed_ratio,
    s.distinct_staff_count,
    s.distinct_store_count,
    s.store_countries,
    RANK() OVER (
        PARTITION BY s.customer_country
        ORDER BY (s.day_amount / NULLIF(s.avg_daily_amount_prev_30d, 0)) DESC,
                 s.day_amount DESC,
                 s.customer_id
    ) AS risk_rank_within_country
FROM scored AS s
WHERE s.day_amount >= 2.0 * s.avg_daily_amount_prev_30d
ORDER BY
    s.customer_country,
    risk_rank_within_country,
    s.payment_day,
    s.customer_id;