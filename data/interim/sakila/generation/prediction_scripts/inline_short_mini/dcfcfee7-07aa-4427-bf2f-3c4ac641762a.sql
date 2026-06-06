WITH customer_monthly AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        ct.d01 AS city_id,
        ct.d02 AS city_name,
        cn.c01 AS country_id,
        cn.c02 AS country_name,
        strftime('%Y-%m', p.p06) AS payment_month,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS monthly_amount,
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
        c.h01,
        c.h03,
        c.h04,
        ct.d01,
        ct.d02,
        cn.c01,
        cn.c02,
        strftime('%Y-%m', p.p06)
),
customer_monthly_prev AS (
    SELECT
        cm.*,
        LAG(cm.monthly_amount) OVER (
            PARTITION BY cm.customer_id
            ORDER BY cm.payment_month
        ) AS prev_month_amount
    FROM customer_monthly AS cm
),
geo_month_stats AS (
    SELECT
        city_id,
        country_id,
        payment_month,
        AVG(monthly_amount) AS city_avg_monthly_amount,
        AVG(monthly_amount) OVER (
            PARTITION BY country_id, payment_month
        ) AS country_avg_monthly_amount
    FROM customer_monthly
    GROUP BY city_id, country_id, payment_month
),
ranked AS (
    SELECT
        cmp.*,
        gms.city_avg_monthly_amount,
        gms.country_avg_monthly_amount,
        RANK() OVER (
            PARTITION BY cmp.country_id, cmp.payment_month
            ORDER BY cmp.monthly_amount DESC
        ) AS country_month_rank
    FROM customer_monthly_prev AS cmp
    JOIN geo_month_stats AS gms
      ON gms.city_id = cmp.city_id
     AND gms.country_id = cmp.country_id
     AND gms.payment_month = cmp.payment_month
)
SELECT
    customer_id,
    first_name,
    last_name,
    country_name,
    city_name,
    payment_month,
    payment_count,
    ROUND(monthly_amount, 2) AS monthly_amount,
    ROUND(city_avg_monthly_amount, 2) AS city_avg_monthly_amount,
    ROUND(country_avg_monthly_amount, 2) AS country_avg_monthly_amount,
    ROUND(prev_month_amount, 2) AS prev_month_amount,
    ROUND(
        CASE
            WHEN prev_month_amount IS NULL OR prev_month_amount = 0 THEN NULL
            ELSE (monthly_amount - prev_month_amount) * 100.0 / prev_month_amount
        END,
        2
    ) AS growth_pct_vs_prev_month,
    staff_count,
    ROUND(max_payment, 2) AS max_payment,
    country_month_rank
FROM ranked
WHERE monthly_amount > 50
   OR monthly_amount > COALESCE(city_avg_monthly_amount, 0) * 1.5
   OR monthly_amount > COALESCE(country_avg_monthly_amount, 0) * 1.5
ORDER BY
    payment_month,
    country_name,
    country_month_rank,
    monthly_amount DESC,
    customer_id;