WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        co.c02 AS country_name,
        ci.d02 AS city_name,
        c.h02 AS home_store_id
    FROM cus c
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ci ON ci.d01 = a.e05
    JOIN cnt co ON co.c01 = ci.d03
),
payments_base AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p03 AS staff_id,
        s.o07 AS staff_store_id,
        cg.country_name,
        cg.home_store_id
    FROM pay p
    JOIN customer_geo cg ON cg.customer_id = p.p02
    JOIN stf s ON s.o01 = p.p03
),
monthly_customer AS (
    SELECT
        customer_id,
        month_start,
        country_name,
        home_store_id,
        COUNT(*) AS payment_count,
        SUM(payment_amount) AS payment_sum,
        COUNT(*) FILTER (WHERE staff_store_id <> home_store_id) AS off_home_staff_payment_count,
        COUNT(DISTINCT staff_id) AS distinct_staff_count
    FROM (
        SELECT
            customer_id, month_start, country_name, home_store_id,
            payment_amount, staff_id, staff_store_id
        FROM payments_base
    )
    GROUP BY
        customer_id,
        month_start,
        country_name,
        home_store_id
),
monthly_with_prev AS (
    SELECT
        mc.*,
        (SELECT AVG(mc2.payment_sum)
         FROM monthly_customer mc2
         WHERE mc2.customer_id = mc.customer_id
           AND mc2.month_start >= date(mc.month_start, '-2 months')
           AND mc2.month_start <  date(mc.month_start, '-0 months')
           AND mc2.month_start <  mc.month_start
        ) AS personal_avg_prev_2mo
    FROM monthly_customer mc
),
monthly_country_stats AS (
    SELECT
        country_name,
        month_start,
        payment_sum,
        payment_count,
        ROW_NUMBER() OVER (PARTITION BY country_name, month_start ORDER BY payment_sum) AS rn,
        COUNT(*) OVER (PARTITION BY country_name, month_start) AS cnt
    FROM monthly_customer
),
country_p95 AS (
    SELECT
        country_name,
        month_start,
        MIN(payment_sum) AS country_p95_payment_sum
    FROM monthly_country_stats
    WHERE rn >= CAST(CEIL(0.95 * cnt) AS INTEGER)
    GROUP BY
        country_name,
        month_start
),
rank_in_country_month AS (
    SELECT
        mc.*,
        c.country_p95_payment_sum,
        RANK() OVER (
            PARTITION BY mc.country_name, mc.month_start
            ORDER BY mc.payment_sum DESC
        ) AS customer_rank_in_country_month
    FROM monthly_with_prev mc
    JOIN country_p95 c
      ON c.country_name = mc.country_name
     AND c.month_start = mc.month_start
)
SELECT
    customer_id,
    country_name,
    month_start AS month,
    payment_count,
    ROUND(payment_sum, 2) AS payment_sum,
    ROUND(personal_avg_prev_2mo, 2) AS personal_avg_prev_2mo,
    ROUND(payment_sum / NULLIF(personal_avg_prev_2mo, 0), 2) AS personal_vs_avg_ratio,
    ROUND(country_p95_payment_sum, 2) AS country_p95_payment_sum,
    ROUND(off_home_staff_payment_count * 1.0 / NULLIF(payment_count, 0), 4) AS off_home_staff_payment_share,
    distinct_staff_count AS distinct_staff_count,
    customer_rank_in_country_month
FROM rank_in_country_month
WHERE personal_avg_prev_2mo IS NOT NULL
  AND personal_avg_prev_2mo > 0
  AND payment_sum >= 3 * personal_avg_prev_2mo
  AND payment_sum > country_p95_payment_sum
ORDER BY
    month,
    country_name,
    customer_rank_in_country_month,
    payment_sum DESC,
    customer_id;