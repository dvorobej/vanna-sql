WITH monthly_customer_payments AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        co.c02 AS country,
        ci.d02 AS city,
        strftime('%Y-%m', p.p06) AS payment_month,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS monthly_sum,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT COALESCE(s.o07, -1)) AS distinct_store_count
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
    JOIN stf AS s ON s.o01 = p.p03
    WHERE p.p04 IS NOT NULL
    GROUP BY
        c.h01, c.h03, c.h04, co.c02, ci.d02, strftime('%Y-%m', p.p06)
),
month_history AS (
    SELECT
        mcp.*,
        AVG(mcp.monthly_sum) OVER (
            PARTITION BY mcp.customer_id
            ORDER BY mcp.payment_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_months_avg_monthly_sum
    FROM monthly_customer_payments AS mcp
),
daily_different_checks AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        COUNT(*) AS payments_in_month,
        COUNT(DISTINCT date(p.p06)) AS distinct_payment_days,
        COUNT(DISTINCT p.p03) AS distinct_staff_count_in_month,
        COUNT(DISTINCT COALESCE(s.o07, -1)) AS distinct_store_count_in_month
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    WHERE p.p04 IS NOT NULL
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
qualified AS (
    SELECT
        mh.*,
        ddc.distinct_payment_days,
        ddc.distinct_staff_count_in_month,
        ddc.distinct_store_count_in_month
    FROM month_history AS mh
    JOIN daily_different_checks AS ddc
      ON ddc.customer_id = mh.customer_id
     AND ddc.payment_month = mh.payment_month
    WHERE mh.prev_months_avg_monthly_sum IS NOT NULL
      AND mh.monthly_sum >= 3 * mh.prev_months_avg_monthly_sum
      AND ddc.payments_in_month >= 3
      AND ddc.distinct_payment_days >= 3
      AND (ddc.distinct_staff_count_in_month >= 2 OR ddc.distinct_store_count_in_month >= 2)
)
SELECT
    q.payment_month AS month,
    q.customer_id,
    q.customer_name,
    q.country,
    q.city,
    q.payment_count,
    ROUND(q.monthly_sum, 2) AS monthly_sum,
    ROUND(q.max_payment, 2) AS max_payment,
    ROUND(CASE WHEN q.monthly_sum = 0 THEN 0 ELSE q.max_payment / q.monthly_sum END, 4) AS max_payment_share,
    q.distinct_staff_count_in_month AS distinct_staff_count,
    q.distinct_store_count_in_month AS distinct_store_count,
    RANK() OVER (
        PARTITION BY q.country, q.payment_month
        ORDER BY q.monthly_sum DESC
    ) AS country_month_rank
FROM qualified AS q
ORDER BY
    q.country,
    q.payment_month,
    country_month_rank,
    q.customer_id;