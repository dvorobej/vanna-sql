WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h02 AS home_store_id,
        cnt.c02 AS country,
        cty.d02 AS city
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
pay_base AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        CAST(p.p05 AS REAL) AS amount,
        p.p03 AS staff_id,
        stf.o07 AS staff_store_id
    FROM pay AS p
    JOIN stf ON stf.o01 = p.p03
),
monthly_customer AS (
    SELECT
        cb.customer_id,
        cb.month_start,
        cg.country,
        COUNT(*) AS payment_count,
        SUM(cb.amount) AS payment_sum,
        COUNT(DISTINCT cb.staff_id) AS staff_count_distinct,
        SUM(CASE WHEN cb.staff_store_id <> cg.home_store_id THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS off_home_staff_payment_share
    FROM pay_base AS cb
    JOIN customer_geo AS cg ON cg.customer_id = cb.customer_id
    GROUP BY
        cb.customer_id,
        cb.month_start,
        cg.country
),
with_personal_prev2 AS (
    SELECT
        mc.*,
        AVG(prev.payment_sum) AS personal_avg_prev2_months_sum
    FROM monthly_customer AS mc
    LEFT JOIN monthly_customer AS prev
        ON prev.customer_id = mc.customer_id
       AND prev.month_start >= date(mc.month_start, '-2 months')
       AND prev.month_start <  date(mc.month_start, '-1 months')
    GROUP BY
        mc.customer_id,
        mc.month_start,
        mc.country,
        mc.payment_count,
        mc.payment_sum,
        mc.staff_count_distinct,
        mc.off_home_staff_payment_share
),
country_month_values AS (
    SELECT
        country,
        month_start,
        payment_sum,
        payment_count,
        RANK() OVER (
            PARTITION BY country, month_start
            ORDER BY payment_sum DESC
        ) AS payment_sum_rank_in_country_month,
        COUNT(*) OVER (PARTITION BY country, month_start) AS cnt_customers_in_month
    FROM monthly_customer
),
country_p95 AS (
    SELECT
        country,
        month_start,
        MIN(payment_sum) AS country_p95_payment_sum
    FROM country_month_values
    WHERE payment_sum_rank_in_country_month >= CAST(0.05 * (cnt_customers_in_month - 1) + 1 AS INTEGER)
    GROUP BY country, month_start
),
scored AS (
    SELECT
        w.*,
        cp.country_p95_payment_sum,
        (w.payment_sum / NULLIF(w.personal_avg_prev2_months_sum, 0)) AS personal_ratio,
        (w.payment_sum / NULLIF(cp.country_p95_payment_sum, 0)) AS vs_country_p95_ratio,
        RANK() OVER (
            PARTITION BY w.country, w.month_start
            ORDER BY w.payment_sum DESC
        ) AS country_month_amount_rank
    FROM with_personal_prev2 AS w
    JOIN country_p95 AS cp
      ON cp.country = w.country
     AND cp.month_start = w.month_start
)
SELECT
    s.customer_id,
    cg.country,
    cg.city,
    strftime('%Y-%m', s.month_start) AS payment_month,
    s.payment_count,
    ROUND(s.payment_sum, 2) AS payment_sum,
    ROUND(s.personal_avg_prev2_months_sum, 2) AS personal_avg_prev2_months_sum,
    ROUND(s.personal_ratio, 3) AS personal_ratio_vs_prev2_avg,
    ROUND(s.country_p95_payment_sum, 2) AS country_p95_payment_sum,
    ROUND(s.off_home_staff_payment_share, 4) AS off_home_staff_payment_share,
    s.staff_count_distinct AS distinct_staff_count,
    s.country_month_amount_rank AS country_month_amount_rank
FROM scored AS s
JOIN customer_geo AS cg
  ON cg.customer_id = s.customer_id
WHERE s.personal_avg_prev2_months_sum IS NOT NULL
  AND s.personal_avg_prev2_months_sum > 0
  AND s.payment_sum >= 3.0 * s.personal_avg_prev2_months_sum
  AND s.payment_sum > s.country_p95_payment_sum
ORDER BY
    cg.country,
    payment_month,
    s.country_month_amount_rank,
    s.payment_sum DESC,
    s.customer_id;