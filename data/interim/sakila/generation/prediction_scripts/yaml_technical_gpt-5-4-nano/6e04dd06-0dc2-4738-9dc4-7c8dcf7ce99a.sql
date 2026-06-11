WITH base AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS customer_first_name,
        c.h04 AS customer_last_name,
        s.o01 AS staff_id,
        s.o07 AS staff_store_id,
        c.h02 AS store_id,
        cn.c01 AS country_id,
        cn.c02 AS country_name,
        date(p.p06, 'start of month') AS month_start,
        p.p05 AS payment_amount
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN stf AS s
        ON s.o01 = p.p03
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ct
        ON ct.d01 = a.e05
    JOIN cnt AS cn
        ON cn.c01 = ct.d03
    WHERE p.p06 IS NOT NULL
),
monthly AS (
    SELECT
        b.customer_id,
        b.customer_first_name,
        b.customer_last_name,
        b.country_id,
        b.country_name,
        b.month_start,
        SUM(b.payment_amount) AS monthly_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT b.staff_id) AS distinct_staff_count,
        COUNT(DISTINCT b.store_id) AS distinct_customer_store_count,
        COUNT(DISTINCT b.staff_store_id) AS distinct_staff_store_count
    FROM base AS b
    GROUP BY
        b.customer_id,
        b.customer_first_name,
        b.customer_last_name,
        b.country_id,
        b.country_name,
        b.month_start
),
with_prev_avg3 AS (
    SELECT
        m.*,
        AVG(monthly_amount) OVER (
            PARTITION BY customer_id
            ORDER BY month_start
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS avg_prev_3_months
    FROM monthly AS m
),
country_month_ranked AS (
    SELECT
        m.*,
        COUNT(*) OVER (
            PARTITION BY country_id, month_start
        ) AS country_cnt,
        ROW_NUMBER() OVER (
            PARTITION BY country_id, month_start
            ORDER BY monthly_amount
        ) AS rn_asc
    FROM monthly AS m
),
country_median AS (
    SELECT
        country_id,
        month_start,
        AVG(monthly_amount) AS country_median_amount
    FROM country_month_ranked
    WHERE rn_asc IN (
        CAST((country_cnt + 1) / 2 AS INTEGER),
        CAST((country_cnt + 2) / 2 AS INTEGER)
    )
    GROUP BY
        country_id,
        month_start
),
country_p95 AS (
    SELECT
        country_id,
        month_start,
        MAX(CASE WHEN rn_asc = CAST((country_cnt * 0.95) AS INTEGER) THEN monthly_amount END) AS p95_low,
        MAX(CASE WHEN rn_asc = CAST((country_cnt * 0.95) + 1 AS INTEGER) THEN monthly_amount END) AS p95_high,
        MAX(CAST((country_cnt * 0.95) AS INTEGER)) AS p95_pos_base,
        MAX(country_cnt) AS country_cnt_max
    FROM country_month_ranked
    GROUP BY country_id, month_start
),
country_p95_final AS (
    SELECT
        r.country_id,
        r.month_start,
        CASE
            WHEN p95_low IS NULL THEN p95_high
            WHEN p95_high IS NULL THEN p95_low
            ELSE p95_low
        END AS country_p95_amount
    FROM country_p95 AS p95
    JOIN (
        SELECT DISTINCT country_id, month_start
        FROM monthly
    ) AS r
      ON r.country_id = p95.country_id
     AND r.month_start = p95.month_start
),
filtered AS (
    SELECT
        w.customer_id,
        w.customer_first_name,
        w.customer_last_name,
        w.country_id,
        w.country_name,
        w.month_start,
        w.monthly_amount,
        w.payment_count,
        w.distinct_staff_count,
        w.distinct_customer_store_count,
        w.distinct_staff_store_count,
        w.avg_prev_3_months,
        cm.country_median_amount,
        p95.country_p95_amount,
        RANK() OVER (
            PARTITION BY w.country_id, w.month_start
            ORDER BY w.monthly_amount DESC
        ) AS customer_rank_in_country
    FROM with_prev_avg3 AS w
    JOIN country_median AS cm
      ON cm.country_id = w.country_id
     AND cm.month_start = w.month_start
    JOIN country_p95_final AS p95
      ON p95.country_id = w.country_id
     AND p95.month_start = w.month_start
)
SELECT
    f.customer_id,
    f.customer_first_name,
    f.customer_last_name,
    f.country_name AS country,
    strftime('%Y-%m', f.month_start) AS month,
    ROUND(f.monthly_amount, 2) AS monthly_amount,
    f.payment_count,
    f.distinct_staff_count,
    f.distinct_customer_store_count AS distinct_h02_store_count,
    f.distinct_staff_store_count AS distinct_stf_store_count,
    ROUND(f.avg_prev_3_months, 2) AS avg_prev_3_months,
    ROUND(f.monthly_amount - f.avg_prev_3_months, 2) AS deviation_from_avg_prev_3,
    ROUND(f.country_median_amount, 2) AS country_median_amount,
    ROUND(f.country_p95_amount, 2) AS country_p95_amount,
    f.customer_rank_in_country
FROM filtered AS f
WHERE f.avg_prev_3_months IS NOT NULL
  AND f.monthly_amount >= 3.0 * f.avg_prev_3_months
  AND f.monthly_amount >= 2.0 * f.country_median_amount
  AND f.customer_rank_in_country <= 5
ORDER BY
    f.country_name,
    f.month_start,
    f.customer_rank_in_country,
    f.customer_id;