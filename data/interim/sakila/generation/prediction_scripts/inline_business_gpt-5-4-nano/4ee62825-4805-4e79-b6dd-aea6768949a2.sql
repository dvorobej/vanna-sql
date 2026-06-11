WITH active_customers AS (
    SELECT h01 AS customer_id, h06 AS address_id
    FROM cus
    WHERE h07 = 'Y'
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        co.c02 AS country_name,
        ct.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ct.d03
    WHERE c.h07 = 'Y'
),
daily_customer AS (
    SELECT
        p.p02 AS customer_id,
        cg.country_name,
        cg.city_name,
        date(p.p06) AS payment_day,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        MIN(p.p06) AS first_payment_ts,
        MAX(p.p06) AS last_payment_ts,
        MAX(CAST(p.p05 AS REAL)) AS max_payment_day
    FROM pay AS p
    JOIN active_customers AS ac ON ac.customer_id = p.p02
    JOIN customer_geo AS cg ON cg.customer_id = p.p02
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY
        p.p02,
        cg.country_name,
        cg.city_name,
        date(p.p06)
),
daily_with_personal_avg AS (
    SELECT
        dc.*,
        COALESCE((
            SELECT AVG(dcp.day_amount)
            FROM daily_customer AS dcp
            WHERE dcp.customer_id = dc.customer_id
              AND dcp.payment_day >= date(dc.payment_day, '-30 day')
              AND dcp.payment_day < dc.payment_day
        ), 0.0) AS personal_avg_daily_30d
    FROM daily_customer AS dc
),
daily_with_country_rank AS (
    SELECT
        dwp.*,
        RANK() OVER (
            PARTITION BY dwp.country_name
            ORDER BY dwp.day_amount DESC
        ) AS country_suspicious_rank_raw,
        COUNT(*) OVER (
            PARTITION BY dwp.country_name
        ) AS country_day_cnt
    FROM daily_with_personal_avg AS dwp
),
country_p95 AS (
    SELECT
        dwr.country_name,
        MAX(CASE
            WHEN dwr.country_suspicious_rank_raw >= CAST((0.05 * dwr.country_day_cnt) AS INTEGER) + 1
            THEN dwr.day_amount
        END) AS p95_day_amount
    FROM daily_with_country_rank AS dwr
    GROUP BY dwr.country_name
),
suspicious AS (
    SELECT
        dwr.*,
        cp95.p95_day_amount,
        (dwr.day_amount - dwr.personal_avg_daily_30d) / NULLIF(dwr.personal_avg_daily_30d, 0.0) AS personal_exceed_ratio
    FROM daily_with_country_rank AS dwr
    JOIN country_p95 AS cp95
        ON cp95.country_name = dwr.country_name
    WHERE dwr.personal_avg_daily_30d > 0
      AND dwr.payment_count >= 3
      AND dwr.staff_count >= 2
      AND dwr.day_amount > 2.0 * dwr.personal_avg_daily_30d
      AND dwr.day_amount > cp95.p95_day_amount
),
final_ranked AS (
    SELECT
        s.*,
        DENSE_RANK() OVER (
            PARTITION BY s.country_name
            ORDER BY personal_exceed_ratio DESC, day_amount DESC, customer_id
        ) AS suspicion_rank_in_country
    FROM suspicious AS s
)
SELECT
    customer_id,
    country_name,
    city_name,
    payment_day AS suspicious_date,
    payment_count,
    ROUND(day_amount, 2) AS day_amount,
    staff_count,
    store_count,
    first_payment_ts AS first_payment_time,
    last_payment_ts AS last_payment_time,
    ROUND(max_payment_day, 2) AS max_payment,
    ROUND(personal_avg_daily_30d, 2) AS personal_avg_daily_30d,
    ROUND(personal_exceed_ratio, 4) AS personal_exceed_ratio,
    suspicion_rank_in_country
FROM final_ranked
ORDER BY
    country_name,
    suspicion_rank_in_country,
    suspicious_date,
    customer_id;