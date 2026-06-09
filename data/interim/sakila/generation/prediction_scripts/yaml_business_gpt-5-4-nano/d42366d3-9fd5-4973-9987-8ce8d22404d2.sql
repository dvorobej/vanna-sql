WITH
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        c.h02 AS home_store_id,
        cn.c01 AS country_id,
        cn.c02 AS country_name,
        ci.d01 AS city_id,
        ci.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS cn ON cn.c01 = ci.d03
),
payment_base AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        cg.customer_name,
        cg.home_store_id,
        cg.country_id,
        cg.country_name,
        cg.city_id,
        cg.city_name,
        date(p.p06, 'start of month') AS month_start,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p03 AS staff_id,
        st.o07 AS staff_store_id
    FROM pay AS p
    JOIN customer_geo AS cg ON cg.customer_id = p.p02
    JOIN stf AS st ON st.o01 = p.p03
),
customer_month AS (
    SELECT
        pb.customer_id,
        pb.customer_name,
        pb.country_id,
        pb.country_name,
        pb.city_id,
        pb.city_name,
        pb.month_start,
        SUM(pb.payment_amount) AS month_payment_sum,
        COUNT(*) AS month_payment_count,
        COUNT(DISTINCT pb.staff_id) AS distinct_staff_count,
        SUM(CASE WHEN pb.staff_store_id <> pb.home_store_id THEN 1 ELSE 0 END) AS off_home_payment_count,
        1.0 * SUM(CASE WHEN pb.staff_store_id <> pb.home_store_id THEN 1 ELSE 0 END) / COUNT(*) AS off_home_payment_share
    FROM payment_base AS pb
    GROUP BY
        pb.customer_id,
        pb.customer_name,
        pb.country_id,
        pb.country_name,
        pb.city_id,
        pb.city_name,
        pb.month_start
),
customer_with_personal_history AS (
    SELECT
        cm.*,
        AVG(month_payment_sum) OVER (
            PARTITION BY customer_id
            ORDER BY month_start
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS personal_avg_prev_2m
    FROM customer_month AS cm
),
country_month_percentiles AS (
    SELECT
        cm.country_id,
        cm.month_start,
        cm.month_payment_sum,
        cm.customer_id,
        COUNT(*) OVER (PARTITION BY cm.country_id, cm.month_start) AS n,
        ROW_NUMBER() OVER (
            PARTITION BY cm.country_id, cm.month_start
            ORDER BY cm.month_payment_sum
        ) AS rn
    FROM customer_month AS cm
),
country_p95 AS (
    SELECT
        country_id,
        month_start,
        MAX(CASE WHEN rn = CAST(0.95 * n AS INTEGER) THEN month_payment_sum END) AS p95_exact
    FROM country_month_percentiles
    GROUP BY country_id, month_start
),
country_p95_fallback AS (
    SELECT
        country_id,
        month_start,
        COALESCE(
            p95_exact,
            MAX(month_payment_sum)
        ) AS p95_value
    FROM (
        SELECT
            cmp.country_id,
            cmp.month_start,
            cmp.month_payment_sum,
            cmp.rn,
            cmp.n,
            CASE
                WHEN cmp.rn = CAST(0.95 * cmp.n AS INTEGER) THEN cmp.month_payment_sum
                ELSE NULL
            END AS p95_exact
        FROM country_month_percentiles AS cmp
    ) x
    LEFT JOIN country_p95 USING (country_id, month_start)
    GROUP BY country_id, month_start, p95_exact
),
country_month_rank AS (
    SELECT
        cm.*,
        RANK() OVER (
            PARTITION BY cm.country_id, cm.month_start
            ORDER BY cm.month_payment_sum DESC
        ) AS country_month_amount_rank
    FROM customer_month AS cm
)
SELECT
    cmr.customer_id,
    cmr.customer_name,
    cmr.country_name AS country,
    cmr.city_name AS city,
    strftime('%Y-%m', cmr.month_start) AS payment_month,
    ROUND(cmr.month_payment_sum, 2) AS month_payment_sum,
    cmr.month_payment_count,
    ROUND(cmr.personal_avg_prev_2m, 2) AS personal_avg_prev_2m,
    ROUND(cmr.off_home_payment_share, 4) AS off_home_payment_share,
    cmr.distinct_staff_count AS distinct_staff_count,
    cmr.country_month_amount_rank AS country_month_amount_rank
FROM country_month_rank AS cmr
JOIN country_p95_fallback AS p95
  ON p95.country_id = cmr.country_id
 AND p95.month_start = cmr.month_start
WHERE cmr.personal_avg_prev_2m IS NOT NULL
  AND cmr.personal_avg_prev_2m > 0
  AND cmr.month_payment_sum > 3.0 * cmr.personal_avg_prev_2m
  AND cmr.month_payment_sum > p95.p95_value
ORDER BY
    cmr.country_name,
    cmr.month_start,
    cmr.country_month_amount_rank,
    cmr.customer_id;