WITH monthly_customer AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS customer_first_name,
        c.h04 AS customer_last_name,
        cn.c01 AS country_id,
        cn.c02 AS country_name,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS monthly_amount,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT c.h02) AS distinct_store_count
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ct
        ON ct.d01 = a.e05
    JOIN cnt AS cn
        ON cn.c01 = ct.d03
    GROUP BY
        c.h01,
        c.h03,
        c.h04,
        cn.c01,
        cn.c02,
        date(p.p06, 'start of month')
),
monthly_with_history AS (
    SELECT
        mc.*,
        AVG(mc.monthly_amount) OVER (
            PARTITION BY mc.customer_id
            ORDER BY mc.month_start
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS avg_prev_3_months
    FROM monthly_customer AS mc
),
country_month_stats AS (
    SELECT
        mwh.*,
        PERCENT_RANK() OVER (
            PARTITION BY mwh.country_id, mwh.month_start
            ORDER BY mwh.monthly_amount
        ) AS pr_country_month
    FROM monthly_with_history AS mwh
),
country_percentiles AS (
    SELECT
        country_id,
        month_start,
        COUNT(*) AS n,
        (n - 1) * 0.95 AS pos95
    FROM (
        SELECT DISTINCT
            country_id,
            month_start
        FROM country_month_stats
    )
),
country_month_sorted AS (
    SELECT
        cms.*,
        ROW_NUMBER() OVER (
            PARTITION BY cms.country_id, cms.month_start
            ORDER BY cms.monthly_amount
        ) AS rn
    FROM country_month_stats AS cms
),
country_month_p95 AS (
    SELECT
        cms.country_id,
        cms.month_start,
        MAX(CASE WHEN cms.rn = CAST(cp.pos95 AS INTEGER) + 1 THEN cms.monthly_amount END) AS amount_at_floor,
        MAX(CASE WHEN cms.rn = CAST(cp.pos95 AS INTEGER) + 2 THEN cms.monthly_amount END) AS amount_at_ceil,
        cp.pos95 - CAST(cp.pos95 AS INTEGER) AS frac
    FROM country_month_sorted AS cms
    JOIN (
        SELECT
            country_id,
            month_start,
            COUNT(*) AS n,
            (COUNT(*) - 1) * 0.95 AS pos95
        FROM monthly_customer
        GROUP BY country_id, month_start
    ) AS cp
      ON cp.country_id = cms.country_id
     AND cp.month_start = cms.month_start
    GROUP BY
        cms.country_id,
        cms.month_start,
        cp.pos95
),
country_month_median AS (
    SELECT
        cms.country_id,
        cms.month_start,
        AVG(cms.monthly_amount) AS median_amount
    FROM (
        SELECT
            country_id,
            month_start,
            monthly_amount,
            ROW_NUMBER() OVER (
                PARTITION BY country_id, month_start
                ORDER BY monthly_amount
            ) AS rn,
            COUNT(*) OVER (
                PARTITION BY country_id, month_start
            ) AS n
        FROM monthly_customer
    ) AS cms
    WHERE cms.rn IN (
        CAST((cms.n + 1) / 2 AS INTEGER),
        CAST((cms.n + 2) / 2 AS INTEGER)
    )
    GROUP BY cms.country_id, cms.month_start
)
SELECT
    cms.customer_id,
    cms.customer_first_name,
    cms.customer_last_name,
    cms.country_name,
    cms.month_start AS month,
    ROUND(cms.monthly_amount, 2) AS monthly_amount,
    cms.payment_count,
    cms.distinct_staff_count,
    cms.distinct_store_count,
    ROUND(cms.avg_prev_3_months, 2) AS avg_prev_3_months,
    ROUND(cmm.median_amount, 2) AS country_median_monthly_amount,
    ROUND(cp95.amount_at_floor + cp95.frac * (cp95.amount_at_ceil - cp95.amount_at_floor), 2) AS country_p95_monthly_amount
FROM monthly_with_history AS cms
JOIN country_month_median AS cmm
    ON cmm.country_id = cms.country_id
   AND cmm.month_start = cms.month_start
JOIN country_month_p95 AS cp95
    ON cp95.country_id = cms.country_id
   AND cp95.month_start = cms.month_start
WHERE cms.avg_prev_3_months IS NOT NULL
  AND cms.monthly_amount >= 3.0 * cms.avg_prev_3_months
  AND cms.monthly_amount >= 2.0 * cmm.median_amount
  AND cms.monthly_amount >= (cp95.amount_at_floor + cp95.frac * (cp95.amount_at_ceil - cp95.amount_at_floor))
ORDER BY
    cms.country_name,
    cms.month_start,
    cms.monthly_amount DESC,
    cms.customer_id;