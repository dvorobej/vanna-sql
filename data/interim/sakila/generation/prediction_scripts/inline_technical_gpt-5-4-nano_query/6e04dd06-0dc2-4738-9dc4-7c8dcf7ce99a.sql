WITH monthly_customer AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month_id,
        SUM(p.p05) AS month_amount,
        COUNT(*) AS month_payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s
        ON s.o01 = p.p03
    GROUP BY
        p.p02,
        strftime('%Y-%m', p.p06)
),
monthly_customer_with_history AS (
    SELECT
        mc.*,
        (
            SELECT AVG(m1.month_amount)
            FROM monthly_customer AS m1
            WHERE m1.customer_id = mc.customer_id
              AND m1.month_id < mc.month_id
              AND m1.month_id >= strftime('%Y-%m', date(mc.month_id || '-01', '-3 months'))
        ) AS avg_prev_3m_amount
    FROM monthly_customer AS mc
),
country_month AS (
    SELECT
        mc.customer_id,
        mc.month_id,
        cty.c01 AS country_id,
        SUM(mc.month_amount) AS country_month_total_amount,
        COUNT(*) AS country_month_customer_count
    FROM monthly_customer_with_history mc
    JOIN cus AS c
        ON c.h01 = mc.customer_id
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty
        ON cty.d01 = a.e05
    WHERE cty.c01 IS NOT NULL
    GROUP BY
        mc.customer_id,
        mc.month_id,
        cty.c01
),
monthly_customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        cty.c01 AS country_id,
        c.h03 AS customer_first_name,
        c.h04 AS customer_last_name,
        c.h02 AS home_store_id
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty
        ON cty.d01 = a.e05
),
country_month_customer_values AS (
    SELECT
        mcwh.customer_id,
        mcwh.month_id,
        g.country_id,
        mcwh.month_amount,
        mcwh.month_payment_count,
        mcwh.staff_count,
        mcwh.store_count,
        ROW_NUMBER() OVER (
            PARTITION BY g.country_id, mcwh.month_id
            ORDER BY mcwh.month_amount
        ) AS rn_asc,
        ROW_NUMBER() OVER (
            PARTITION BY g.country_id, mcwh.month_id
            ORDER BY mcwh.month_amount DESC
        ) AS rn_desc,
        COUNT(*) OVER (
            PARTITION BY g.country_id, mcwh.month_id
        ) AS country_n
    FROM monthly_customer_with_history mcwh
    JOIN monthly_customer_geo g
        ON g.customer_id = mcwh.customer_id
),
country_month_median AS (
    SELECT
        country_id,
        month_id,
        AVG(month_amount) AS median_month_amount
    FROM (
        SELECT
            country_id,
            month_id,
            month_amount,
            rn_asc,
            country_n,
            CAST((country_n + 1) / 2 AS INTEGER) AS lower_mid,
            CAST((country_n + 2) / 2 AS INTEGER) AS upper_mid
        FROM country_month_customer_values
    )
    WHERE rn_asc = lower_mid OR rn_asc = upper_mid
    GROUP BY country_id, month_id
),
country_month_top5pct AS (
    SELECT
        *,
        CEIL(country_n * 0.05) AS top5pct_n
    FROM (
        SELECT
            cmcv.*,
            ROW_NUMBER() OVER (
                PARTITION BY cmcv.country_id, cmcv.month_id
                ORDER BY cmcv.month_amount DESC
            ) AS rn_desc2
        FROM country_month_customer_values cmcv
    )
),
candidates AS (
    SELECT
        cmcv.customer_id,
        g.customer_first_name,
        g.customer_last_name,
        g.country_id,
        cmcv.month_id,
        cmcv.month_amount,
        cmcv.month_payment_count,
        cmcv.staff_count,
        cmcv.store_count,
        cmcv.avg_prev_3m_amount,
        cmm.median_month_amount,
        (cmcv.month_amount * 1.0) / NULLIF(cmcv.avg_prev_3m_amount, 0) AS ratio_vs_own_avg3m,
        (cmcv.month_amount * 1.0) / NULLIF(cmm.median_month_amount, 0) AS ratio_vs_country_median,
        DENSE_RANK() OVER (
            PARTITION BY g.country_id, cmcv.month_id
            ORDER BY cmcv.month_amount DESC
        ) AS country_month_rank_desc,
        cmcv.country_n,
        cmcv.rn_desc2
    FROM country_month_top5pct cmcv
    JOIN monthly_customer_geo g
        ON g.customer_id = cmcv.customer_id
    LEFT JOIN country_month_median cmm
        ON cmm.country_id = cmcv.country_id
       AND cmm.month_id = cmcv.month_id
    WHERE cmcv.avg_prev_3m_amount IS NOT NULL
)
SELECT
    customer_id,
    customer_first_name,
    customer_last_name,
    country_id,
    month_id,
    ROUND(month_amount, 2) AS month_amount,
    month_payment_count,
    staff_count,
    store_count,
    ROUND(avg_prev_3m_amount, 2) AS avg_prev_3m_amount,
    ROUND(median_month_amount, 2) AS country_median_month_amount,
    ROUND(ratio_vs_own_avg3m, 2) AS ratio_vs_own_avg3m,
    ROUND(ratio_vs_country_median, 2) AS ratio_vs_country_median,
    country_month_rank_desc,
    country_n
FROM candidates
WHERE ratio_vs_own_avg3m >= 3
  AND ratio_vs_country_median >= 2
  AND rn_desc2 <= CEIL(country_n * 0.05)
ORDER BY
    country_id,
    month_id,
    ratio_vs_own_avg3m DESC,
    month_amount DESC,
    customer_id;