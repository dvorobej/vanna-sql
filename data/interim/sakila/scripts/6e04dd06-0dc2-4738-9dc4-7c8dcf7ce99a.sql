WITH RECURSIVE
month_bounds AS (
    SELECT
        date(MIN(p06), 'start of month') AS min_month,
        date(MAX(p06), 'start of month') AS max_month
    FROM pay
),
months(month_start) AS (
    SELECT min_month
    FROM month_bounds
    WHERE min_month IS NOT NULL

    UNION ALL

    SELECT date(month_start, '+1 month')
    FROM months
    CROSS JOIN month_bounds
    WHERE month_start < max_month
),
customer_country AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS customer_first_name,
        c.h04 AS customer_last_name,
        co.c01 AS country_id,
        co.c02 AS country_name
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ci
        ON ci.d01 = a.e05
    JOIN cnt AS co
        ON co.c01 = ci.d03
),
customer_months AS (
    SELECT
        cc.customer_id,
        cc.customer_first_name,
        cc.customer_last_name,
        cc.country_id,
        cc.country_name,
        m.month_start
    FROM customer_country AS cc
    CROSS JOIN months AS m
),
payment_agg AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        SUM(CAST(p.p05 AS REAL)) AS monthly_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT s.o07) AS distinct_store_count
    FROM pay AS p
    JOIN stf AS s
        ON s.o01 = p.p03
    GROUP BY
        p.p02,
        date(p.p06, 'start of month')
),
monthly_base AS (
    SELECT
        cm.customer_id,
        cm.customer_first_name,
        cm.customer_last_name,
        cm.country_id,
        cm.country_name,
        cm.month_start,
        COALESCE(pa.monthly_amount, 0.0) AS monthly_amount,
        COALESCE(pa.payment_count, 0) AS payment_count,
        COALESCE(pa.distinct_staff_count, 0) AS distinct_staff_count,
        COALESCE(pa.distinct_store_count, 0) AS distinct_store_count
    FROM customer_months AS cm
    LEFT JOIN payment_agg AS pa
        ON pa.customer_id = cm.customer_id
       AND pa.month_start = cm.month_start
),
monthly_with_history AS (
    SELECT
        mb.*,
        AVG(mb.monthly_amount) OVER (
            PARTITION BY mb.customer_id
            ORDER BY mb.month_start
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS avg_prev_3_months_amount,
        COUNT(*) OVER (
            PARTITION BY mb.customer_id
            ORDER BY mb.month_start
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prev_3_months_count
    FROM monthly_base AS mb
),
country_month_ranked_for_median AS (
    SELECT
        mwh.country_id,
        mwh.month_start,
        mwh.monthly_amount,
        ROW_NUMBER() OVER (
            PARTITION BY mwh.country_id, mwh.month_start
            ORDER BY mwh.monthly_amount
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY mwh.country_id, mwh.month_start
        ) AS cnt
    FROM monthly_with_history AS mwh
),
country_month_median AS (
    SELECT
        country_id,
        month_start,
        AVG(monthly_amount) AS country_median_monthly_amount
    FROM country_month_ranked_for_median
    WHERE rn IN (
        CAST((cnt + 1) / 2 AS INTEGER),
        CAST((cnt + 2) / 2 AS INTEGER)
    )
    GROUP BY
        country_id,
        month_start
),
country_month_top AS (
    SELECT
        mwh.customer_id,
        mwh.country_id,
        mwh.month_start,
        PERCENT_RANK() OVER (
            PARTITION BY mwh.country_id, mwh.month_start
            ORDER BY mwh.monthly_amount DESC
        ) AS country_month_percent_rank
    FROM monthly_with_history AS mwh
)
SELECT
    mwh.customer_id,
    mwh.customer_first_name,
    mwh.customer_last_name,
    mwh.country_name,
    strftime('%Y-%m', mwh.month_start) AS payment_month,
    ROUND(mwh.monthly_amount, 2) AS monthly_payment_amount,
    mwh.payment_count,
    mwh.distinct_staff_count,
    mwh.distinct_store_count,
    ROUND(mwh.avg_prev_3_months_amount, 2) AS avg_prev_3_months_amount,
    ROUND(cmm.country_median_monthly_amount, 2) AS country_median_monthly_amount,
    ROUND(cmt.country_month_percent_rank, 4) AS country_month_percent_rank
FROM monthly_with_history AS mwh
JOIN country_month_median AS cmm
    ON cmm.country_id = mwh.country_id
   AND cmm.month_start = mwh.month_start
JOIN country_month_top AS cmt
    ON cmt.customer_id = mwh.customer_id
   AND cmt.country_id = mwh.country_id
   AND cmt.month_start = mwh.month_start
WHERE mwh.payment_count > 0
  AND mwh.prev_3_months_count = 3
  AND mwh.avg_prev_3_months_amount > 0
  AND cmm.country_median_monthly_amount > 0
  AND mwh.monthly_amount >= 3 * mwh.avg_prev_3_months_amount
  AND mwh.monthly_amount >= 2 * cmm.country_median_monthly_amount
  AND cmt.country_month_percent_rank <= 0.05
ORDER BY
    mwh.month_start,
    mwh.country_name,
    mwh.monthly_amount DESC,
    mwh.customer_id;