SELECT AVG(m2.payment_sum)
            FROM monthly_customer AS m2
            WHERE m2.customer_id = mc.customer_id
              AND m2.month_start >= date(mc.month_start, '-2 months')
              AND m2.month_start <  mc.month_start
        ) AS personal_prev2_avg_sum
    FROM monthly_customer AS mc
),
country_month_stats AS (
    SELECT
        country,
        month_start,
        payment_sum,
        COUNT(*) OVER (PARTITION BY country, month_start) AS cnt,
        ROW_NUMBER() OVER (PARTITION BY country, month_start ORDER BY payment_sum) AS rn
    FROM monthly_customer
),
country_p95 AS (
    SELECT
        country,
        month_start,
        MIN(payment_sum) AS country_p95_payment_sum
    FROM country_month_stats
    WHERE rn >= CAST((0.95 * cnt + 0.5) AS INTEGER)
      AND cnt > 0
    GROUP BY country, month_start
),
scored AS (
    SELECT
        wpp2.customer_id,
        wpp2.country,
        wpp2.month_start,
        wpp2.payment_count,
        wpp2.payment_sum,
        wpp2.off_home_staff_share,
        wpp2.distinct_staff_count,
        wpp2.personal_prev2_avg_sum,
        cp.country_p95_payment_sum,
        (wpp2.payment_sum / NULLIF(wpp2.personal_prev2_avg_sum, 0)) AS personal_sum_ratio,
        RANK() OVER (
            PARTITION BY wpp2.country, wpp2.month_start
            ORDER BY wpp2.payment_sum DESC
        ) AS country_month_payment_rank
    FROM with_personal_prev2 AS wpp2
    JOIN country_p95 AS cp
      ON cp.country = wpp2.country
     AND cp.month_start = wpp2.month_start
)
SELECT
    strftime('%Y-%m', month_start) AS payment_month,
    customer_id,
    country,
    payment_count,
    ROUND(payment_sum, 2) AS payment_sum,
    ROUND(personal_prev2_avg_sum, 2) AS personal_prev2_avg_sum,
    ROUND(personal_sum_ratio, 2) AS personal_sum_ratio,
    ROUND(country_p95_payment_sum, 2) AS country_p95_payment_sum,
    off_home_staff_share,
    distinct_staff_count AS different_staff_count,
    country_month_payment_rank
FROM scored
WHERE personal_prev2_avg_sum IS NOT NULL
  AND personal_prev2_avg_sum > 0
  AND payment_sum >= 3.0 * personal_prev2_avg_sum
  AND payment_sum > country_p95_payment_sum
ORDER BY
    payment_month,
    country,
    country_month_payment_rank,
    payment_sum DESC,
    customer_id;