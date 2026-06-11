SELECT COUNT(*)
            FROM monthly_customer AS x
            WHERE x.customer_id = mc.customer_id
              AND x.month_start >= date(mc.month_start, '-2 months')
              AND x.month_start <  mc.month_start
        ) AS prev2_months_count
    FROM monthly_customer AS mc
    JOIN (
        SELECT
            mc2.customer_id,
            mc2.country_id,
            mc2.country_name,
            mc2.month_start,
            AVG(m2.payment_sum) AS personal_avg_prev2_sum
        FROM monthly_customer AS mc2
        LEFT JOIN monthly_customer AS m2
          ON m2.customer_id = mc2.customer_id
         AND m2.month_start >= date(mc2.month_start, '-2 months')
         AND m2.month_start <  mc2.month_start
        GROUP BY
            mc2.customer_id,
            mc2.country_id,
            mc2.country_name,
            mc2.month_start
    ) AS p2
      ON p2.customer_id = mc.customer_id
     AND p2.country_id = mc.country_id
     AND p2.month_start = mc.month_start
     AND p2.country_name = mc.country_name
),
country_month_totals AS (
    SELECT
        country_id,
        month_start,
        payment_sum AS payment_sum_for_day,
        ROW_NUMBER() OVER (
            PARTITION BY country_id, month_start
            ORDER BY payment_sum DESC
        ) AS rn_desc,
        COUNT(*) OVER (PARTITION BY country_id, month_start) AS cnt_customers
    FROM monthly_customer
),
country_p95 AS (
    SELECT
        country_id,
        month_start,
        MAX(payment_sum_for_day) AS country_p95_payment_sum
    FROM country_month_totals
    WHERE rn_desc <= CAST(0.05 * cnt_customers AS INTEGER)
    GROUP BY
        country_id,
        month_start
),
final_scored AS (
    SELECT
        p.customer_id,
        p.country_id,
        p.country_name,
        p.month_start,
        p.payment_count,
        p.payment_sum,
        p.off_home_staff_payment_share,
        p.distinct_staff_count,
        p.personal_avg_prev2_sum,
        cp.country_p95_payment_sum,
        (p.payment_sum * 1.0 / NULLIF(p.personal_avg_prev2_sum, 0)) AS ratio_to_personal_avg_prev2,
        (p.payment_sum * 1.0 / NULLIF(cp.country_p95_payment_sum, 0)) AS ratio_to_country_p95
    FROM personal_prev2_filtered AS p
    JOIN country_p95 AS cp
      ON cp.country_id = p.country_id
     AND cp.month_start = p.month_start
    WHERE p.prev2_months_count = 2
      AND p.personal_avg_prev2_sum > 0
      AND p.payment_sum >= 3.0 * p.personal_avg_prev2_sum
      AND p.payment_sum > cp.country_p95_payment_sum
),
ranked AS (
    SELECT
        fs.*,
        RANK() OVER (
            PARTITION BY fs.country_id, fs.month_start
            ORDER BY fs.payment_sum DESC
        ) AS client_country_month_rank
    FROM final_scored AS fs
)
SELECT
    client_country_month_rank AS risk_rank_in_country,
    customer_id,
    country_name,
    date(month_start, 'start of month') AS month_start,
    payment_count,
    ROUND(payment_sum, 2) AS payment_sum,
    ROUND(off_home_staff_payment_share, 4) AS off_home_staff_payment_share,
    distinct_staff_count AS distinct_staff_count,
    ROUND(personal_avg_prev2_sum, 2) AS personal_avg_prev2_sum,
    ROUND(country_p95_payment_sum, 2) AS country_p95_payment_sum
FROM ranked
ORDER BY
    country_name,
    month_start,
    risk_rank_in_country,
    payment_sum DESC,
    customer_id;