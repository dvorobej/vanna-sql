WITH monthly_customer_data AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        c.h02 AS home_store_id,
        cn.c02 AS country_name,
        ct.d02 AS city_name,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT cat.g01) AS distinct_category_count,
        SUM(CASE WHEN i.n03 <> c.h02 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS foreign_store_share
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    JOIN flm AS f ON f.i01 = i.n02
    JOIN flc AS flc ON flc.l01 = f.i01
    JOIN cat AS cat ON cat.g01 = flc.l02
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS cn ON cn.c01 = ct.d03
    GROUP BY c.h01, c.h03, c.h04, c.h02, cn.c02, ct.d02, strftime('%Y-%m', p.p06)
),
monthly_with_history AS (
    SELECT
        *,
        AVG(monthly_amount) OVER (
            PARTITION BY customer_id
            ORDER BY payment_month
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prev_3_month_avg
    FROM monthly_customer_data
),
filtered_customers AS (
    SELECT *
    FROM monthly_with_history
    WHERE prev_3_month_avg IS NOT NULL
      AND monthly_amount > 3 * prev_3_month_avg
      AND distinct_staff_count >= 2
      AND distinct_category_count >= 3
),
ranked_customers AS (
    SELECT
        *,
        RANK() OVER (
            PARTITION BY country_name, payment_month
            ORDER BY monthly_amount DESC
        ) AS country_rank
    FROM filtered_customers
)
SELECT
    payment_month,
    country_name,
    city_name,
    customer_name,
    ROUND(monthly_amount, 2) AS total_payment_sum,
    payment_count,
    ROUND(max_payment, 2) AS max_single_payment,
    ROUND(foreign_store_share, 4) AS foreign_store_share,
    country_rank
FROM ranked_customers
ORDER BY
    payment_month DESC,
    country_name,
    country_rank;