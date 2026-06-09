WITH payment_enriched AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p03 AS staff_id,
        s.o07 AS store_id
    FROM pay AS p
    JOIN stf AS s
        ON s.o01 = p.p03
),
customer_geo AS (
    SELECT
        cu.h01 AS customer_id,
        ct.c02 AS country,
        cty.d02 AS city
    FROM cus AS cu
    JOIN adr AS a
        ON a.e01 = cu.h06
    JOIN cty
        ON cty.d01 = a.e05
    JOIN cnt AS ct
        ON ct.c01 = cty.d03
),
daily_by_customer AS (
    SELECT
        pe.customer_id,
        pe.payment_date,
        SUM(pe.payment_amount) AS daily_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT pe.staff_id) AS staff_count,
        COUNT(DISTINCT pe.store_id) AS store_count
    FROM payment_enriched AS pe
    GROUP BY
        pe.customer_id,
        pe.payment_date
),
daily_with_avgs AS (
    SELECT
        dbc.*,
        (
            SELECT AVG(dbc_prev.daily_amount)
            FROM daily_by_customer AS dbc_prev
            WHERE dbc_prev.customer_id = dbc.customer_id
              AND dbc_prev.payment_date >= date(dbc.payment_date, '-30 day')
              AND dbc_prev.payment_date < dbc.payment_date
        ) AS personal_avg_prev_30d
    FROM daily_by_customer AS dbc
),
country_daily_stats AS (
    SELECT
        d.customer_id,
        cg.country,
        d.payment_date,
        d.daily_amount
    FROM daily_with_avgs AS d
    JOIN customer_geo AS cg
        ON cg.customer_id = d.customer_id
),
country_avg_prev_30d AS (
    SELECT
        cds.customer_id,
        cds.country,
        cds.payment_date,
        (
            SELECT AVG(cds_prev.daily_amount)
            FROM country_daily_stats AS cds_prev
            WHERE cds_prev.country = cds.country
              AND cds_prev.payment_date >= date(cds.payment_date, '-30 day')
              AND cds_prev.payment_date < cds.payment_date
        ) AS country_avg_prev_30d_daily
    FROM country_daily_stats AS cds
),
final_cases AS (
    SELECT
        d.customer_id,
        cg.country,
        cg.city,
        d.payment_date,
        d.payment_count,
        d.daily_amount,
        d.staff_count,
        d.store_count,
        d.daily_amount - d.personal_avg_prev_30d AS deviation_personal_avg,
        d.daily_amount - cavg.country_avg_prev_30d_daily AS deviation_country_avg,
        DENSE_RANK() OVER (
            PARTITION BY cg.country, d.payment_date
            ORDER BY d.daily_amount DESC
        ) AS country_suspicious_rank
    FROM daily_with_avgs AS d
    JOIN customer_geo AS cg
        ON cg.customer_id = d.customer_id
    JOIN country_avg_prev_30d AS cavg
        ON cavg.customer_id = d.customer_id
       AND cavg.payment_date = d.payment_date
       AND cavg.country = cg.country
    WHERE d.personal_avg_prev_30d IS NOT NULL
      AND cavg.country_avg_prev_30d_daily IS NOT NULL
      AND d.personal_avg_prev_30d > 0
      AND cavg.country_avg_prev_30d_daily > 0
      AND d.daily_amount > 3.0 * d.personal_avg_prev_30d
      AND d.daily_amount > cavg.country_avg_prev_30d_daily
      AND (d.staff_count >= 2 OR d.store_count >= 2)
)
SELECT
    customer_id,
    country,
    city,
    payment_date AS date,
    ROUND(daily_amount, 2) AS daily_sum,
    payment_count,
    ROUND(deviation_personal_avg, 2) AS deviation_from_personal_avg,
    ROUND(deviation_country_avg, 2) AS deviation_from_country_avg,
    staff_count,
    store_count,
    country_suspicious_rank AS country_rank_by_suspicious_sum
FROM final_cases
ORDER BY
    country,
    payment_date,
    country_suspicious_rank,
    daily_sum DESC,
    customer_id;