WITH customer_monthly AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        a.e05 AS city_id,
        ct.d02 AS city_name,
        cn.c01 AS country_id,
        cn.c02 AS country_name,
        strftime('%Y-%m', p.p06) AS month,
        COUNT(p.p01) AS payment_count,
        SUM(p.p05) AS total_amount,
        AVG(p.p05) AS average_check,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS staff_count
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ct
        ON ct.d01 = a.e05
    JOIN cnt AS cn
        ON cn.c01 = ct.d03
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 < '2006-01-01'
    GROUP BY
        c.h01, c.h03, c.h04,
        a.e05, ct.d02, cn.c01, cn.c02,
        strftime('%Y-%m', p.p06)
),
city_month_avg AS (
    SELECT
        city_id,
        month,
        AVG(total_amount) AS avg_city_amount
    FROM customer_monthly
    GROUP BY city_id, month
),
country_month_ranked AS (
    SELECT
        cm.*,
        PERCENT_RANK() OVER (
            PARTITION BY cm.country_id, cm.month
            ORDER BY cm.total_amount
        ) AS country_percent_rank,
        LAG(cm.total_amount) OVER (
            PARTITION BY cm.customer_id
            ORDER BY cm.month
        ) AS prev_month_amount
    FROM customer_monthly AS cm
),
selected AS (
    SELECT
        cmr.*,
        cma.avg_city_amount
    FROM country_month_ranked AS cmr
    JOIN city_month_avg AS cma
      ON cma.city_id = cmr.city_id
     AND cma.month = cmr.month
    WHERE cmr.total_amount >= cma.avg_city_amount * 3
       OR cmr.country_percent_rank >= 0.95
)
SELECT
    customer_id,
    first_name,
    last_name,
    city_name,
    country_name,
    month,
    payment_count,
    ROUND(total_amount, 2) AS total_amount,
    ROUND(average_check, 2) AS average_check,
    ROUND(avg_city_amount, 2) AS avg_city_amount,
    ROUND(prev_month_amount, 2) AS prev_month_amount,
    ROUND(
        CASE
            WHEN prev_month_amount IS NOT NULL AND prev_month_amount <> 0
            THEN (total_amount - prev_month_amount) * 100.0 / prev_month_amount
        END,
        2
    ) AS month_over_month_growth_pct,
    staff_count,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(country_percent_rank, 4) AS country_percent_rank
FROM selected
ORDER BY
    month,
    country_name,
    total_amount DESC,
    customer_id;