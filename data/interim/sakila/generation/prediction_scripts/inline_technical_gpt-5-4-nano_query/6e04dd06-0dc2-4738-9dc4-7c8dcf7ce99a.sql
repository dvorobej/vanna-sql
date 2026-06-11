WITH month_payments AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS customer_first_name,
        c.h04 AS customer_last_name,
        co.c01 AS country_id,
        co.c02 AS country_name,
        strftime('%Y-%m', p.p06) AS month,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS month_sum
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ci
        ON ci.d01 = a.e05
    JOIN cnt AS co
        ON co.c01 = ci.d03
    WHERE p.p06 IS NOT NULL
    GROUP BY
        c.h01, c.h03, c.h04, co.c01, co.c02, strftime('%Y-%m', p.p06)
),
month_dims AS (
    SELECT
        c.h01 AS customer_id,
        strftime('%Y-%m', p.p06) AS month,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT s.o07) AS distinct_store_count
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN stf AS s
        ON s.o01 = p.p03
    GROUP BY
        c.h01,
        strftime('%Y-%m', p.p06)
),
month_stats AS (
    SELECT
        mp.*,
        md.distinct_staff_count,
        md.distinct_store_count,
        AVG(mp.month_sum) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.month
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS avg_prev_3_months_sum
    FROM month_payments AS mp
    LEFT JOIN month_dims AS md
        ON md.customer_id = mp.customer_id
       AND md.month = mp.month
),
country_month_ranked AS (
    SELECT
        ms.country_id,
        ms.month,
        ms.customer_id,
        ms.month_sum,
        RANK() OVER (
            PARTITION BY ms.country_id, ms.month
            ORDER BY ms.month_sum DESC
        ) AS country_month_rank_desc,
        COUNT(*) OVER (
            PARTITION BY ms.country_id, ms.month
        ) AS country_month_customer_count
    FROM month_stats AS ms
),
country_month_median AS (
    SELECT
        cmr.country_id,
        cmr.month,
        AVG(1.0 * cmr.month_sum) AS country_month_median_sum
    FROM (
        SELECT
            cmr.*,
            ROW_NUMBER() OVER (
                PARTITION BY cmr.country_id, cmr.month
                ORDER BY cmr.month_sum
            ) AS rn_asc
        FROM country_month_ranked AS cmr
    ) AS t
    JOIN (
        SELECT
            country_id,
            month,
            COUNT(*) AS cnt
        FROM country_month_ranked
        GROUP BY country_id, month
    ) AS x
      ON x.country_id = t.country_id
     AND x.month = t.month
    WHERE t.rn_asc = CAST((x.cnt + 1) / 2 AS INT)
       OR t.rn_asc = CAST((x.cnt + 2) / 2 AS INT)
    GROUP BY t.country_id, t.month
),
final_scoring AS (
    SELECT
        ms.customer_id,
        ms.customer_first_name,
        ms.customer_last_name,
        ms.country_id,
        ms.country_name,
        ms.month,
        ms.payment_count,
        ROUND(ms.month_sum, 2) AS month_sum,
        ms.distinct_staff_count,
        ms.distinct_store_count,
        ms.avg_prev_3_months_sum,
        cmm.country_month_median_sum,
        cmr.country_month_rank_desc,
        cmr.country_month_customer_count,
        CASE
            WHEN ms.avg_prev_3_months_sum IS NULL OR ms.avg_prev_3_months_sum = 0 THEN NULL
            ELSE ms.month_sum / ms.avg_prev_3_months_sum
        END AS growth_vs_prev3_ratio,
        CASE
            WHEN cmm.country_month_median_sum IS NULL OR cmm.country_month_median_sum = 0 THEN NULL
            ELSE ms.month_sum / cmm.country_month_median_sum
        END AS ratio_vs_country_median
    FROM month_stats AS ms
    JOIN country_month_ranked AS cmr
      ON cmr.country_id = ms.country_id
     AND cmr.month = ms.month
     AND cmr.customer_id = ms.customer_id
    JOIN country_month_median AS cmm
      ON cmm.country_id = ms.country_id
     AND cmm.month = ms.month
)
SELECT
    fs.customer_id,
    fs.customer_first_name,
    fs.customer_last_name,
    fs.country_name,
    fs.month,
    fs.payment_count,
    fs.month_sum,
    fs.distinct_staff_count,
    fs.distinct_store_count,
    ROUND(fs.avg_prev_3_months_sum, 2) AS avg_prev_3_months_sum,
    fs.growth_vs_prev3_ratio,
    ROUND(fs.country_month_median_sum, 2) AS country_month_median_sum,
    fs.ratio_vs_country_median,
    fs.country_month_rank_desc AS country_month_rank_desc,
    fs.country_month_customer_count
FROM final_scoring AS fs
WHERE fs.avg_prev_3_months_sum IS NOT NULL
  AND fs.avg_prev_3_months_sum > 0
  AND fs.country_month_median_sum IS NOT NULL
  AND fs.month_sum >= 3.0 * fs.avg_prev_3_months_sum
  AND fs.month_sum >= 2.0 * fs.country_month_median_sum
  AND fs.country_month_rank_desc <= CAST(0.05 * fs.country_month_customer_count + 0.0000001 AS INT) + 1
ORDER BY
    fs.country_name,
    fs.month,
    fs.growth_vs_prev3_ratio DESC,
    fs.month_sum DESC,
    fs.customer_id;