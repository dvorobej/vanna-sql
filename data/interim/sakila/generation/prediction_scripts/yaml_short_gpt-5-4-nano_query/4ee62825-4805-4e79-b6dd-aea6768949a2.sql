WITH daily_base AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        MIN(p.p06) AS first_operation_ts,
        MAX(p.p06) AS last_operation_ts,
        MAX(CAST(p.p05 AS REAL)) AS max_payment_amount
    FROM pay AS p
    JOIN stf AS s
        ON s.o01 = p.p03
    GROUP BY
        p.p02,
        DATE(p.p06)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        city.d02 AS city_name,
        cnt.c02 AS country_name,
        cnt.c01 AS country_id
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS city
        ON city.d01 = a.e05
    JOIN cnt
        ON cnt.c01 = city.d03
),
daily_with_context AS (
    SELECT
        db.*,
        cg.city_name,
        cg.country_id,
        cg.country_name,
        COALESCE((
            SELECT AVG(db_prev.day_amount)
            FROM daily_base AS db_prev
            WHERE db_prev.customer_id = db.customer_id
              AND db_prev.payment_date >= date(db.payment_date, '-30 day')
              AND db_prev.payment_date < db.payment_date
        ), 0.0) AS personal_avg_prev_30d
    FROM daily_base AS db
    JOIN customer_geo AS cg
        ON cg.customer_id = db.customer_id
),
country_p95 AS (
    SELECT
        country_id,
        payment_date,
        day_amount,
        PERCENT_RANK() OVER (PARTITION BY country_id ORDER BY day_amount) AS pr
    FROM daily_with_context
),
country_threshold AS (
    SELECT
        country_id,
        day_amount AS p95_day_amount
    FROM (
        SELECT
            country_id,
            day_amount,
            ROW_NUMBER() OVER (
                PARTITION BY country_id
                ORDER BY day_amount DESC
            ) AS rn,
            COUNT(*) OVER (PARTITION BY country_id) AS cnt
        FROM daily_with_context
    )
    WHERE rn = CAST(CEIL(0.95 * cnt) AS INT)
),
candidate_days AS (
    SELECT
        dwc.*,
        ct.p95_day_amount,
        CASE
            WHEN dwc.personal_avg_prev_30d > 0 THEN dwc.day_amount / dwc.personal_avg_prev_30d
        END AS ratio_vs_personal_avg,
        (dwc.day_amount - dwc.personal_avg_prev_30d) AS exceed_over_personal_avg
    FROM daily_with_context AS dwc
    JOIN country_threshold AS ct
        ON ct.country_id = dwc.country_id
)
SELECT
    cd.customer_id,
    cd.city_name,
    cd.country_name,
    cd.payment_date,
    cd.payment_count,
    ROUND(cd.day_amount, 2) AS day_amount,
    cd.staff_count AS distinct_staff_count,
    cd.store_count AS distinct_store_count,
    cd.first_operation_ts,
    cd.last_operation_ts,
    ROUND(cd.max_payment_amount, 2) AS max_payment_amount,
    RANK() OVER (
        PARTITION BY cd.country_id
        ORDER BY cd.exceed_over_personal_avg DESC, cd.day_amount DESC
    ) AS suspicion_rank_in_country
FROM candidate_days AS cd
JOIN cus AS c
    ON c.h01 = cd.customer_id
WHERE c.h07 = 'Y'
  AND cd.payment_count >= 3
  AND cd.staff_count >= 2
  AND cd.day_amount > 3.0 * cd.personal_avg_prev_30d
  AND cd.day_amount > cd.p95_day_amount
ORDER BY
    cd.country_name,
    suspicion_rank_in_country,
    cd.day_amount DESC,
    cd.payment_date;