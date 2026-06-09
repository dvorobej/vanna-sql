WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h02 AS home_store_id,
        co.c02 AS country,
        ci.d02 AS city
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
),
monthly_base AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p03 AS staff_id,
        s.o07 AS staff_store_id,
        cg.home_store_id,
        cg.country
    FROM pay AS p
    JOIN customer_geo AS cg ON cg.customer_id = p.p02
    JOIN stf AS s ON s.o01 = p.p03
),
monthly_customer AS (
    SELECT
        customer_id,
        month_start,
        country,
        SUM(payment_amount) AS month_sum,
        COUNT(*) AS month_payment_count,
        SUM(CASE WHEN staff_store_id <> home_store_id THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS off_home_staff_payment_share,
        COUNT(DISTINCT staff_id) AS distinct_staff_count
    FROM monthly_base
    GROUP BY customer_id, month_start, country
),
personal_prev2 AS (
    SELECT
        mc.*,
        (
            SELECT AVG(mc2.month_sum)
            FROM monthly_customer AS mc2
            WHERE mc2.customer_id = mc.customer_id
              AND mc2.month_start < mc.month_start
              AND mc2.month_start >= date(mc.month_start, '-2 months')
        ) AS personal_avg_prev2_month_sum,
        (
            SELECT AVG(mc2.month_payment_count * 1.0)
            FROM monthly_customer AS mc2
            WHERE mc2.customer_id = mc.customer_id
              AND mc2.month_start < mc.month_start
              AND mc2.month_start >= date(mc.month_start, '-2 months')
        ) AS personal_avg_prev2_month_count,
        (
            SELECT COUNT(*)
            FROM monthly_customer AS mc2
            WHERE mc2.customer_id = mc.customer_id
              AND mc2.month_start < mc.month_start
              AND mc2.month_start >= date(mc.month_start, '-2 months')
        ) AS prev2_months_count
    FROM monthly_customer AS mc
),
country_months_ranked AS (
    SELECT
        mc.country,
        mc.month_start,
        mc.month_sum,
        COUNT(*) OVER (PARTITION BY mc.country, mc.month_start) AS cnt_in_country_month
    FROM monthly_customer AS mc
),
country_p95 AS (
    SELECT
        cmr.country,
        cmr.month_start,
        MIN(cmr2.month_sum) AS country_p95_month_sum
    FROM country_months_ranked AS cmr
    JOIN (
        SELECT
            mc.country,
            mc.month_start,
            mc.month_sum,
            ROW_NUMBER() OVER (
                PARTITION BY mc.country, mc.month_start
                ORDER BY mc.month_sum
            ) AS rn_asc,
            COUNT(*) OVER (PARTITION BY mc.country, mc.month_start) AS cnt_in_country_month
        FROM monthly_customer AS mc
    ) AS cmr2
      ON cmr2.country = cmr.country
     AND cmr2.month_start = cmr.month_start
    WHERE cmr2.rn_asc >= CAST(0.95 * (cmr2.cnt_in_country_month + 1) AS INTEGER)
    GROUP BY cmr.country, cmr.month_start
),
suspicious AS (
    SELECT
        p.customer_id,
        p.month_start,
        p.country,
        p.month_payment_count,
        p.month_sum,
        p.off_home_staff_payment_share,
        p.distinct_staff_count,
        p.personal_avg_prev2_month_sum,
        p.prev2_months_count,
        (p.month_sum / NULLIF(p.personal_avg_prev2_month_sum, 0)) AS month_sum_ratio_to_personal_avg,
        cp.country_p95_month_sum,
        RANK() OVER (
            PARTITION BY p.country, p.month_start
            ORDER BY p.month_sum DESC
        ) AS customer_rank_in_country_month
    FROM personal_prev2 AS p
    JOIN country_p95 AS cp
      ON cp.country = p.country
     AND cp.month_start = p.month_start
    WHERE p.prev2_months_count = 2
      AND p.personal_avg_prev2_month_sum IS NOT NULL
      AND p.personal_avg_prev2_month_sum > 0
      AND p.month_sum >= 3.0 * p.personal_avg_prev2_month_sum
      AND p.month_sum > cp.country_p95_month_sum
)
SELECT
    month_start AS month,
    customer_id,
    country,
    (SELECT city FROM customer_geo WHERE customer_id = suspicious.customer_id LIMIT 1) AS city,
    month_payment_count AS payment_count,
    ROUND(month_sum, 2) AS month_sum,
    ROUND(personal_avg_prev2_month_sum, 2) AS personal_avg_prev2_month_sum,
    ROUND(month_sum_ratio_to_personal_avg, 2) AS ratio_to_personal_avg,
    ROUND(cp.country_p95_month_sum, 2) AS country_p95_month_sum,
    ROUND(off_home_staff_payment_share, 4) AS off_home_staff_payment_share,
    distinct_staff_count AS distinct_staff_count,
    customer_rank_in_country_month AS customer_rank_in_country_month
FROM suspicious
JOIN country_p95 AS cp
  ON cp.country = suspicious.country
 AND cp.month_start = suspicious.month_start
ORDER BY
    country,
    month_start,
    customer_rank_in_country_month,
    month_sum DESC,
    customer_id;