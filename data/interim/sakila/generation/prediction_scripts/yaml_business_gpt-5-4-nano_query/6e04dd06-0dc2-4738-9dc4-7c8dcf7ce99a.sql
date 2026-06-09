WITH monthly_customer AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        strftime('%Y-%m', p.p06) AS month,
        SUM(p.p05) AS month_amount,
        COUNT(*) AS month_payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ci
        ON ci.d01 = a.e05
    JOIN cnt
        ON cnt.c01 = ci.d03
    JOIN stf AS s
        ON s.o01 = p.p03
    GROUP BY
        c.h01,
        c.h03,
        c.h04,
        cnt.c01,
        cnt.c02,
        strftime('%Y-%m', p.p06)
),
monthly_with_history AS (
    SELECT
        mc.*,
        (
            SELECT AVG(mh.month_amount)
            FROM monthly_customer AS mh
            WHERE mh.customer_id = mc.customer_id
              AND mh.month < mc.month
              AND mh.month >= strftime('%Y-%m', date(mc.month || '-01', '-3 months'))
        ) AS avg_prev_3_month_amount
    FROM monthly_customer AS mc
),
country_months_rank AS (
    SELECT
        mwh.*,
        PERCENT_RANK() OVER (
            PARTITION BY country_id, month
            ORDER BY month_amount
        ) AS pct_rank_asc,
        COUNT(*) OVER (
            PARTITION BY country_id, month
        ) AS country_month_customer_count
    FROM monthly_with_history AS mwh
),
country_month_median AS (
    SELECT
        country_id,
        month,
        AVG(1.0 * month_amount) AS country_month_median_amount
    FROM (
        SELECT
            cm.*,
            ROW_NUMBER() OVER (
                PARTITION BY country_id, month
                ORDER BY month_amount
            ) AS rn,
            COUNT(*) OVER (
                PARTITION BY country_id, month
            ) AS cnt_rows
        FROM monthly_customer AS cm
    ) x
    WHERE rn IN (
        CAST((cnt_rows + 1) / 2 AS INTEGER),
        CAST((cnt_rows + 2) / 2 AS INTEGER)
    )
    GROUP BY country_id, month
)
SELECT
    cmr.customer_id,
    cmr.first_name,
    cmr.last_name,
    cmr.country_name,
    cmr.month,
    ROUND(cmr.month_amount, 2) AS month_amount,
    cmr.month_payment_count,
    cmr.staff_count,
    cmr.store_count,
    ROUND(cmr.avg_prev_3_month_amount, 2) AS avg_prev_3_month_amount,
    ROUND(cmr.month_amount / NULLIF(cmr.avg_prev_3_month_amount, 0), 2) AS ratio_to_own_history,
    ROUND(cmm.country_month_median_amount, 2) AS country_month_median_amount,
    ROUND(cmr.month_amount / NULLIF(cmm.country_month_median_amount, 0), 2) AS ratio_to_country_median,
    cmr.pct_rank_asc,
    RANK() OVER (
        PARTITION BY cmr.country_id, cmr.month
        ORDER BY cmr.month_amount DESC
    ) AS country_month_volume_rank_desc
FROM country_months_rank AS cmr
JOIN country_month_median AS cmm
    ON cmm.country_id = cmr.country_id
   AND cmm.month = cmr.month
WHERE cmr.avg_prev_3_month_amount IS NOT NULL
  AND cmr.avg_prev_3_month_amount > 0
  AND cmr.month_amount >= 3.0 * cmr.avg_prev_3_month_amount
  AND cmr.month_amount >= 2.0 * cmm.country_month_median_amount
  AND cmr.month_amount IS NOT NULL
  AND cmr.pct_rank_asc >= 0.95
ORDER BY
    cmr.country_name,
    cmr.month,
    country_month_volume_rank_desc,
    cmr.customer_id;