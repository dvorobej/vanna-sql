WITH monthly_customer AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        c.h02 AS home_store_id,
        co.c02 AS country,
        ci.d02 AS city,
        strftime('%Y-%m', p.p06) AS month,
        COUNT(p.p01) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS month_sum,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN stf AS s ON s.o01 = p.p03
    JOIN adr AS ca ON ca.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = ca.e05
    JOIN cnt AS co ON co.c01 = ci.d03
    GROUP BY
        c.h01, c.h03, c.h04, c.h02, co.c02, ci.d02, strftime('%Y-%m', p.p06)
),
with_prev3_avg AS (
    SELECT
        mc.*,
        (
            SELECT AVG(mc2.month_sum)
            FROM monthly_customer mc2
            WHERE mc2.customer_id = mc.customer_id
              AND date(mc2.month || '-01') >= date(mc.month || '-01', '-3 months')
              AND date(mc2.month || '-01') <  date(mc.month || '-01')
        ) AS avg_prev3_month_sum
    FROM monthly_customer mc
),
country_months AS (
    SELECT
        wc.*,
        DENSE_RANK() OVER (
            PARTITION BY wc.country, wc.month
            ORDER BY wc.month_sum DESC
        ) AS country_month_rank,
        COUNT(*) OVER (
            PARTITION BY wc.country, wc.month
        ) AS country_month_total_cnt
    FROM with_prev3_avg wc
),
country_month_median AS (
    SELECT
        cm.country,
        cm.month,
        AVG(cm2.month_sum) AS country_median_month_sum
    FROM country_months cm
    JOIN country_months cm2
      ON cm2.country = cm.country
     AND cm2.month = cm.month
     AND cm2.country_month_rank IN (
        CAST( (cm.country_month_total_cnt + 1) / 2 AS INTEGER ),
        CAST( (cm.country_month_total_cnt + 2) / 2 AS INTEGER )
     )
    GROUP BY
        cm.country,
        cm.month
)
SELECT
    cm.customer_id,
    cm.first_name || ' ' || cm.last_name AS customer_name,
    cm.country,
    cm.city,
    cm.month,
    cm.payment_count,
    ROUND(cm.month_sum, 2) AS month_sum,
    cm.staff_count AS distinct_staff_count,
    cm.store_count AS distinct_store_count,
    ROUND(cm.avg_prev3_month_sum, 2) AS avg_prev3_month_sum,
    ROUND(
        CASE
            WHEN cm.avg_prev3_month_sum IS NULL OR cm.avg_prev3_month_sum = 0 THEN NULL
            ELSE cm.month_sum / cm.avg_prev3_month_sum
        END,
        4
    ) AS growth_vs_own_history_ratio,
    ROUND(cmm.country_median_month_sum, 2) AS country_median_month_sum,
    cm.country_month_rank AS country_month_rank,
    cm.country_month_total_cnt AS country_month_total_customers,
    ROUND(
        CASE
            WHEN cmm.country_median_month_sum IS NULL OR cmm.country_median_month_sum = 0 THEN NULL
            ELSE cm.month_sum / cmm.country_median_month_sum
        END,
        4
    ) AS month_sum_vs_country_median_ratio
FROM country_months cm
JOIN country_month_median cmm
  ON cmm.country = cm.country
 AND cmm.month = cm.month
WHERE
    cm.avg_prev3_month_sum IS NOT NULL
    AND cm.avg_prev3_month_sum > 0
    AND cm.month_sum >= 3.0 * cm.avg_prev3_month_sum
    AND cmm.country_median_month_sum IS NOT NULL
    AND cmm.country_median_month_sum > 0
    AND cm.month_sum >= 2.0 * cmm.country_median_month_sum
    AND cm.country_month_rank <= ((cm.country_month_total_cnt + 19) / 20)   -- top 5%
ORDER BY
    cm.country,
    cm.month,
    cm.month_sum DESC,
    cm.customer_id;