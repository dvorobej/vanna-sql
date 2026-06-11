WITH payment_details AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_day,
        p.p01 AS payment_id,
        CAST(p.p05 AS REAL) AS amount,
        p.p03 AS staff_id,
        s2.o07 AS staff_store_id,
        stc.store_country_id AS customer_country_id,
        stc.city_id AS customer_city_id,
        stf.o07 AS payment_store_id,
        stp.store_country_id AS payment_country_id
    FROM pay AS p
    JOIN stf AS stf
        ON stf.o01 = p.p03
    JOIN sto AS stc
        ON stc.j01 = stf.o07
    JOIN sto AS stp
        ON stp.j01 = stf.o07
    JOIN (SELECT 1 AS dummy) AS x ON 1=1
),
daily_rollup AS (
    SELECT
        pd.customer_id,
        pd.payment_day,
        COUNT(pd.payment_id) AS payment_count,
        SUM(pd.amount) AS day_amount,
        COUNT(DISTINCT pd.staff_id) AS distinct_staff_count,
        COUNT(DISTINCT pd.staff_store_id) AS distinct_store_count,
        SUM(CASE WHEN pd.payment_country_id <> pd.customer_country_id THEN 1 ELSE 0 END) AS payments_other_country_count
    FROM payment_details AS pd
    GROUP BY pd.customer_id, pd.payment_day
),
daily_with_baseline AS (
    SELECT
        dr.*,
        COALESCE((
            SELECT AVG(drb.day_amount)
            FROM daily_rollup AS drb
            WHERE drb.customer_id = dr.customer_id
              AND drb.payment_day >= DATE(dr.payment_day, '-30 day')
              AND drb.payment_day < dr.payment_day
        ), 0.0) AS avg_prev_30d
    FROM daily_rollup AS dr
),
suspicious_days AS (
    SELECT
        dwr.*,
        (CASE
            WHEN dwr.avg_prev_30d > 0 THEN dwr.day_amount / dwr.avg_prev_30d
            ELSE NULL
         END) AS exceed_ratio
    FROM daily_with_baseline AS dwr
    WHERE dwr.avg_prev_30d > 0
      AND dwr.payment_count >= 3
      AND dwr.day_amount >= 2.0 * dwr.avg_prev_30d
      AND dwr.distinct_staff_count >= 1
      AND dwr.distinct_store_count >= 1
      AND dwr.payments_other_country_count > 0
),
country_ranked AS (
    SELECT
        s.customer_id,
        s.payment_day,
        s.payment_count,
        s.day_amount,
        s.distinct_staff_count,
        s.distinct_store_count,
        s.payments_other_country_count,
        s.exceed_ratio,
        RANK() OVER (
            PARTITION BY ctry.c01
            ORDER BY s.exceed_ratio DESC, s.day_amount DESC
        ) AS day_exceed_rank_in_customer_country
    FROM suspicious_days AS s
    JOIN cus AS c
        ON c.h01 = s.customer_id
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS city
        ON city.d01 = a.e05
    JOIN cnt AS ctry
        ON ctry.c01 = city.d03
    WHERE s.payment_day >= '2005-01-01'
      AND s.payment_day <  '2006-01-01'
),
customer_summary AS (
    SELECT
        customer_id,
        COUNT(*) AS suspicious_days_count
    FROM suspicious_days
    GROUP BY customer_id
)
SELECT
    cr.customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    ctry.c02 AS customer_country,
    city.d02 AS customer_city,
    cr.payment_day AS suspicious_date,
    cr.payment_count,
    ROUND(cr.day_amount, 2) AS day_amount,
    cr.distinct_staff_count,
    cr.distinct_store_count,
    ROUND(cr.exceed_ratio, 3) AS exceed_ratio,
    cr.day_exceed_rank_in_customer_country,
    cs.suspicious_days_count
FROM country_ranked AS cr
JOIN cus AS c
    ON c.h01 = cr.customer_id
JOIN adr AS a
    ON a.e01 = c.h06
JOIN cty AS city
    ON city.d01 = a.e05
JOIN cnt AS ctry
    ON ctry.c01 = city.d03
JOIN customer_summary AS cs
    ON cs.customer_id = cr.customer_id
ORDER BY
    ctry.c02,
    cr.day_exceed_rank_in_customer_country,
    cr.payment_day,
    cr.customer_id;