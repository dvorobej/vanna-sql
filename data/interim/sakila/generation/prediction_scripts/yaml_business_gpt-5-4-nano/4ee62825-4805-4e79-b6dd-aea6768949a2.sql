WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        ci.d02 AS city_name,
        co.c02 AS country_name,
        co.c01 AS country_id
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ci
        ON ci.d01 = a.e05
    JOIN cnt AS co
        ON co.c01 = ci.d03
),
daily_pay AS (
    SELECT
        p.p02 AS customer_id,
        p.p06 AS payment_ts,
        date(p.p06) AS payment_day,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p03 AS staff_id,
        st.o07 AS store_id
    FROM pay AS p
    JOIN stf AS st
        ON st.o01 = p.p03
),
daily_rollup AS (
    SELECT
        dp.customer_id,
        cg.customer_name,
        cg.city_name,
        cg.country_id,
        cg.country_name,
        dp.payment_day,
        COUNT(*) AS payment_count,
        SUM(dp.payment_amount) AS day_amount,
        MAX(dp.payment_amount) AS max_payment,
        COUNT(DISTINCT dp.staff_id) AS distinct_staff_count,
        COUNT(DISTINCT dp.store_id) AS distinct_store_count,
        MIN(dp.payment_ts) AS first_payment_ts,
        MAX(dp.payment_ts) AS last_payment_ts
    FROM daily_pay AS dp
    JOIN customer_geo AS cg
        ON cg.customer_id = dp.customer_id
    GROUP BY
        dp.customer_id,
        cg.customer_name,
        cg.city_name,
        cg.country_id,
        cg.country_name,
        dp.payment_day
),
daily_with_personal_hist AS (
    SELECT
        dr.*,
        (
            SELECT AVG(dr2.day_amount)
            FROM daily_rollup AS dr2
            WHERE dr2.customer_id = dr.customer_id
              AND dr2.payment_day >= date(dr.payment_day, '-30 day')
              AND dr2.payment_day < dr.payment_day
        ) AS personal_avg_day_30d
    FROM daily_rollup AS dr
),
country_day_distribution AS (
    SELECT
        dwh.country_id,
        dwh.payment_day,
        dwh.day_amount,
        PERCENT_RANK() OVER (
            PARTITION BY dwh.country_id
            ORDER BY dwh.day_amount
        ) AS day_percent_rank
    FROM daily_with_personal_hist AS dwh
),
country_p95 AS (
    SELECT DISTINCT
        cdd.country_id,
        cdd.payment_day
    FROM country_day_distribution AS cdd
    WHERE cdd.day_percent_rank >= 0.95
),
flagged AS (
    SELECT
        dwh.*,
        (dwh.day_amount - dwh.personal_avg_day_30d) AS deviation_from_personal_avg,
        (dwh.day_amount / NULLIF(dwh.personal_avg_day_30d, 0)) AS exceed_factor,
        DENSE_RANK() OVER (
            PARTITION BY dwh.country_id
            ORDER BY (dwh.day_amount / NULLIF(dwh.personal_avg_day_30d, 0)) DESC,
                     dwh.day_amount DESC
        ) AS suspicious_rank_in_country
    FROM daily_with_personal_hist AS dwh
    JOIN country_p95 AS p95
      ON p95.country_id = dwh.country_id
     AND p95.payment_day = dwh.payment_day
    JOIN cus AS c
      ON c.h01 = dwh.customer_id
    WHERE
        c.h07 = 'Y'
        AND dwh.payment_count >= 3
        AND dwh.personal_avg_day_30d IS NOT NULL
        AND dwh.personal_avg_day_30d > 0
        AND dwh.day_amount > 2 * dwh.personal_avg_day_30d
        AND dwh.distinct_staff_count >= 2
        AND (dwh.distinct_store_count >= 1 OR dwh.distinct_staff_count >= 2)
)
SELECT
    f.customer_id,
    f.customer_name,
    f.city_name,
    f.country_name,
    f.payment_day AS suspicious_day,
    f.payment_count,
    ROUND(f.day_amount, 2) AS day_total_amount,
    f.distinct_staff_count AS involved_staff_count,
    f.distinct_store_count AS involved_store_count,
    f.first_payment_ts,
    f.last_payment_ts,
    ROUND(f.max_payment, 2) AS max_payment,
    ROUND(f.exceed_factor, 2) AS exceed_factor_vs_personal_avg_30d,
    f.suspicious_rank_in_country AS suspicious_rank_in_country
FROM flagged AS f
ORDER BY
    f.country_name,
    f.suspicious_rank_in_country,
    f.day_amount DESC,
    f.payment_day,
    f.customer_id;