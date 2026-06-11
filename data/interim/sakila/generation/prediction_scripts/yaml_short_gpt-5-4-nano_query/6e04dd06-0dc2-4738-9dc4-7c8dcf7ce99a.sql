WITH monthly_base AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month_key,
        SUM(p.p05) AS month_sum,
        COUNT(p.p01) AS month_payment_count,
        COUNT(DISTINCT p.p03) AS staff_count_distinct,
        COUNT(DISTINCT s.o07) AS store_count_distinct,
        GROUP_CONCAT(DISTINCT (s.o02 || ' ' || s.o03)) AS staff_names_distinct,
        GROUP_CONCAT(DISTINCT s.o07) AS store_ids_distinct
    FROM pay AS p
    JOIN stf AS s
        ON s.o01 = p.p03
    GROUP BY
        p.p02,
        strftime('%Y-%m', p.p06)
),
monthly_with_country AS (
    SELECT
        mb.*,
        co.c02 AS country_name
    FROM monthly_base AS mb
    JOIN cus AS c
        ON c.h01 = mb.customer_id
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ci
        ON ci.d01 = a.e05
    JOIN cnt AS co
        ON co.c01 = ci.d03
),
monthly_with_history AS (
    SELECT
        mwc.*,
        (
            SELECT AVG(m2.month_sum)
            FROM monthly_with_country AS m2
            WHERE m2.customer_id = mwc.customer_id
              AND m2.month_key < mwc.month_key
            ORDER BY m2.month_key DESC
            LIMIT 3
        ) AS avg_prev_3_months_sum
    FROM monthly_with_country AS mwc
),
country_month_median AS (
    SELECT
        country_name,
        month_key,
        AVG(month_sum * 1.0) AS country_median_month_sum
    FROM (
        SELECT
            mwc.country_name,
            mwc.month_key,
            mwc.month_sum,
            ROW_NUMBER() OVER (
                PARTITION BY mwc.country_name, mwc.month_key
                ORDER BY mwc.month_sum
            ) AS rn,
            COUNT(*) OVER (
                PARTITION BY mwc.country_name, mwc.month_key
            ) AS cnt
        FROM monthly_with_country AS mwc
    ) t
    WHERE t.rn IN (
        CAST((t.cnt + 1) / 2 AS INTEGER),
        CAST((t.cnt + 2) / 2 AS INTEGER)
    )
    GROUP BY
        country_name,
        month_key
),
ranked_country AS (
    SELECT
        mwh.*,
        cmm.country_median_month_sum,
        PERCENT_RANK() OVER (
            PARTITION BY mwh.country_name, mwh.month_key
            ORDER BY mwh.month_sum
        ) AS prate_low,
        CUME_DIST() OVER (
            PARTITION BY mwh.country_name, mwh.month_key
            ORDER BY mwh.month_sum
        ) AS cume_dist_asc
    FROM monthly_with_history AS mwh
    JOIN country_month_median AS cmm
      ON cmm.country_name = mwh.country_name
     AND cmm.month_key = mwh.month_key
),
filtered AS (
    SELECT
        rc.*,
        (
            rc.month_sum - rc.avg_prev_3_months_sum
        ) / NULLIF(rc.avg_prev_3_months_sum, 0) AS growth_vs_avg_prev_3,
        RANK() OVER (
            PARTITION BY rc.country_name, rc.month_key
            ORDER BY rc.month_sum DESC
        ) AS country_month_rank_desc,
        COUNT(*) OVER (
            PARTITION BY rc.country_name, rc.month_key
        ) AS country_month_customers_cnt
    FROM ranked_country AS rc
    WHERE
        rc.avg_prev_3_months_sum IS NOT NULL
        AND rc.avg_prev_3_months_sum > 0
        AND rc.month_sum >= 3.0 * rc.avg_prev_3_months_sum
        AND rc.month_sum >= 2.0 * rc.country_median_month_sum
        AND rc.month_sum IS NOT NULL
        AND (
            rc.cume_dist_asc >= 0.95
        )
)
SELECT
    f.customer_id,
    c.h03 AS customer_first_name,
    c.h04 AS customer_last_name,
    f.country_name,
    f.month_key AS month,
    f.month_payment_count AS payment_count_in_month,
    ROUND(f.month_sum, 2) AS month_payment_sum,
    f.staff_count_distinct AS distinct_staff_count,
    f.store_count_distinct AS distinct_store_count,
    ROUND(f.avg_prev_3_months_sum, 2) AS avg_prev_3_months_sum,
    ROUND(f.country_median_month_sum, 2) AS country_month_median_month_sum,
    ROUND(f.growth_vs_avg_prev_3, 2) AS growth_ratio_vs_avg_prev_3_minus1,
    f.country_month_rank_desc AS country_month_rank_desc,
    f.country_month_customers_cnt AS country_month_customers_count
FROM filtered AS f
JOIN cus AS c
  ON c.h01 = f.customer_id
ORDER BY
    f.country_name,
    f.month_key,
    f.month_sum DESC;