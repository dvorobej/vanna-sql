WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        co.c02 AS customer_country,
        ci.d02 AS customer_city
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
),
payment_days AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_day,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT s.o07) AS distinct_store_count,
        COUNT(DISTINCT CASE WHEN st_country.c02 = cg.customer_country THEN s.o07 END) AS distinct_home_store_count,
        COUNT(DISTINCT CASE WHEN st_country.c02 <> cg.customer_country THEN s.o07 END) AS distinct_foreign_store_count,
        SUM(CASE WHEN st_country.c02 <> cg.customer_country THEN 1 ELSE 0 END) AS foreign_store_payment_count,
        SUM(CASE WHEN st_country.c02 <> cg.customer_country THEN CAST(p.p05 AS REAL) ELSE 0 END) AS foreign_store_amount
    FROM pay AS p
    JOIN customer_geo AS cg ON cg.customer_id = p.p02
    JOIN stf AS s ON s.o01 = p.p03
    JOIN sto AS sto ON sto.j01 = s.o07
    JOIN adr AS sa ON sa.e01 = sto.j03
    JOIN cty AS sci ON sci.d01 = sa.e05
    JOIN cnt AS st_country ON st_country.c01 = sci.d03
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY
        p.p02,
        DATE(p.p06)
),
with_prev_avg AS (
    SELECT
        pd.*,
        (
            SELECT AVG(CAST(p2_day.day_amount AS REAL))
            FROM payment_days AS p2_day
            WHERE p2_day.customer_id = pd.customer_id
              AND p2_day.payment_day >= DATE(pd.payment_day, '-30 day')
              AND p2_day.payment_day < pd.payment_day
        ) AS avg_day_amount_prev_30d
    FROM payment_days AS pd
),
flagged AS (
    SELECT
        w.customer_id,
        w.payment_day,
        w.payment_count,
        w.day_amount,
        w.distinct_staff_count,
        w.distinct_store_count,
        w.foreign_store_payment_count,
        w.foreign_store_amount,
        w.avg_day_amount_prev_30d,
        (w.day_amount / NULLIF(w.avg_day_amount_prev_30d, 0)) AS exceed_ratio
    FROM with_prev_avg AS w
    WHERE w.payment_count >= 3
      AND w.avg_day_amount_prev_30d IS NOT NULL
      AND w.avg_day_amount_prev_30d > 0
      AND w.day_amount >= 2.0 * w.avg_day_amount_prev_30d
      AND w.foreign_store_payment_count >= 1
),
daily_store_countries AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_day,
        GROUP_CONCAT(DISTINCT st_country.c02) AS store_countries
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    JOIN sto AS sto ON sto.j01 = s.o07
    JOIN adr AS sa ON sa.e01 = sto.j03
    JOIN cty AS sci ON sci.d01 = sa.e05
    JOIN cnt AS st_country ON st_country.c01 = sci.d03
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY
        p.p02,
        DATE(p.p06)
),
ranked AS (
    SELECT
        f.*,
        cg.customer_country,
        DENSE_RANK() OVER (
            PARTITION BY cg.customer_country
            ORDER BY f.exceed_ratio DESC, f.day_amount DESC, f.customer_id
        ) AS suspicion_rank_in_country
    FROM flagged AS f
    JOIN customer_geo AS cg ON cg.customer_id = f.customer_id
)
SELECT
    r.customer_id,
    cg.customer_city,
    r.customer_country,
    r.payment_day AS suspicious_date,
    r.payment_count,
    ROUND(r.day_amount, 2) AS day_payment_amount,
    ROUND(r.avg_day_amount_prev_30d, 2) AS avg_day_amount_prev_30d,
    r.distinct_staff_count,
    r.distinct_store_count,
    COALESCE(dsc.store_countries, '') AS store_countries,
    r.suspicion_rank_in_country
FROM ranked AS r
JOIN customer_geo AS cg ON cg.customer_id = r.customer_id
LEFT JOIN daily_store_countries AS dsc
    ON dsc.customer_id = r.customer_id
   AND dsc.payment_day = r.payment_day
ORDER BY
    r.customer_country,
    r.suspicion_rank_in_country,
    r.payment_day,
    r.customer_id;