WITH base AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06, 'start of month') AS month_start,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p03 AS staff_id,
        s.o07 AS store_id
    FROM pay AS p
    JOIN stf AS s
      ON s.o01 = p.p03
),
monthly AS (
    SELECT
        b.customer_id,
        b.month_start,
        COUNT(*) AS payment_count,
        SUM(b.payment_amount) AS monthly_sum,
        COUNT(DISTINCT b.staff_id) AS staff_count,
        COUNT(DISTINCT b.store_id) AS store_count
    FROM base AS b
    GROUP BY
        b.customer_id,
        b.month_start
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt ON cnt.c01 = ci.d03
),
monthly_geo AS (
    SELECT
        m.*,
        cg.country_id,
        cg.country_name
    FROM monthly AS m
    JOIN customer_geo AS cg
      ON cg.customer_id = m.customer_id
),
hist AS (
    SELECT
        mg.*,
        AVG(mg2.monthly_sum) AS avg_prev_3_months_sum
    FROM monthly_geo AS mg
    LEFT JOIN monthly_geo AS mg2
      ON mg2.customer_id = mg.customer_id
     AND mg2.month_start < mg.month_start
     AND mg2.month_start >= DATE(mg.month_start, '-3 months')
    GROUP BY
        mg.customer_id,
        mg.month_start,
        mg.payment_count,
        mg.monthly_sum,
        mg.staff_count,
        mg.store_count,
        mg.country_id,
        mg.country_name
),
country_month AS (
    SELECT
        mg.country_id,
        mg.month_start,
        mg.monthly_sum,
        COUNT(*) OVER (PARTITION BY mg.country_id, mg.month_start) AS country_cnt
    FROM monthly_geo AS mg
),
country_ranked AS (
    SELECT
        cm.*,
        DENSE_RANK() OVER (
            PARTITION BY cm.country_id, cm.month_start
            ORDER BY cm.monthly_sum DESC
        ) AS country_sum_rank_desc
    FROM country_month AS cm
),
country_median AS (
    SELECT
        t.country_id,
        t.month_start,
        AVG(t.monthly_sum) AS country_median_sum
    FROM (
        SELECT
            cm.*,
            ROW_NUMBER() OVER (
                PARTITION BY cm.country_id, cm.month_start
                ORDER BY cm.monthly_sum
            ) AS rn_asc
        FROM country_month AS cm
    ) AS t
    GROUP BY
        t.country_id,
        t.month_start
    HAVING
        t.rn_asc IN (
            (COUNT(*) FILTER OVER (PARTITION BY t.country_id, t.month_start) + 1) / 2,
            (COUNT(*) FILTER OVER (PARTITION BY t.country_id, t.month_start) + 2) / 2
        )
),
qualified AS (
    SELECT
        h.customer_id,
        h.month_start,
        h.payment_count,
        h.monthly_sum,
        h.staff_count,
        h.store_count,
        h.country_id,
        h.country_name,
        h.avg_prev_3_months_sum,
        cmd.country_median_sum,
        DENSE_RANK() OVER (
            PARTITION BY h.country_id, h.month_start
            ORDER BY h.monthly_sum DESC
        ) AS country_rank_desc,
        COUNT(*) OVER (
            PARTITION BY h.country_id, h.month_start
        ) AS country_customers_in_month
    FROM hist AS h
    JOIN (
        SELECT
            cm.country_id,
            cm.month_start,
            AVG(cm2.monthly_sum) AS country_median_sum
        FROM (
            SELECT DISTINCT country_id, month_start
            FROM monthly_geo
        ) AS base_m
        JOIN (
            SELECT
                mg.country_id,
                mg.month_start,
                mg.monthly_sum,
                ROW_NUMBER() OVER (
                    PARTITION BY mg.country_id, mg.month_start
                    ORDER BY mg.monthly_sum
                ) AS rn_asc,
                COUNT(*) OVER (
                    PARTITION BY mg.country_id, mg.month_start
                ) AS cnt_in_month
            FROM monthly_geo AS mg
        ) AS cm2
          ON cm2.country_id = base_m.country_id
         AND cm2.month_start = base_m.month_start
        JOIN monthly_geo AS cm
          ON cm.country_id = cm2.country_id
         AND cm.month_start = cm2.month_start
        WHERE cm2.rn_asc IN ( (cm2.cnt_in_month + 1) / 2, (cm2.cnt_in_month + 2) / 2 )
        GROUP BY
            cm.country_id,
            cm.month_start
    ) AS cmd
      ON cmd.country_id = h.country_id
     AND cmd.month_start = h.month_start
)
SELECT
    q.customer_id,
    q.month_start AS month,
    c.h03 AS customer_first_name,
    c.h04 AS customer_last_name,
    q.country_name,
    q.payment_count,
    ROUND(q.monthly_sum, 2) AS monthly_sum,
    q.staff_count,
    q.store_count,
    ROUND(q.avg_prev_3_months_sum, 2) AS avg_prev_3_months_sum,
    ROUND(q.country_median_sum, 2) AS country_median_monthly_sum,
    ROUND(q.monthly_sum / NULLIF(q.avg_prev_3_months_sum, 0), 2) AS growth_vs_own_avg_prev_3_months,
    ROUND(q.monthly_sum / NULLIF(q.country_median_sum, 0), 2) AS growth_vs_country_median,
    q.country_rank_desc AS country_monthly_rank_desc,
    q.country_customers_in_month
FROM qualified AS q
JOIN cus AS c
  ON c.h01 = q.customer_id
WHERE q.avg_prev_3_months_sum IS NOT NULL
  AND q.avg_prev_3_months_sum > 0
  AND q.monthly_sum >= 3.0 * q.avg_prev_3_months_sum
  AND q.country_median_sum IS NOT NULL
  AND q.country_median_sum > 0
  AND q.monthly_sum >= 2.0 * q.country_median_sum
  AND q.country_rank_desc <= CAST(0.05 * q.country_customers_in_month AS INTEGER) + 1
ORDER BY
    q.country_name,
    q.month_start,
    q.country_rank_desc,
    q.monthly_sum DESC;