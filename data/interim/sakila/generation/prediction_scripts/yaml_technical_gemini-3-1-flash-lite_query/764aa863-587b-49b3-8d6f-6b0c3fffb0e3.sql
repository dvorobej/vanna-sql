WITH monthly_customer_data AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS total_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT fc.l02) AS category_count,
        SUM(CASE WHEN i.n03 <> c.h02 THEN 1 ELSE 0 END) AS foreign_store_payment_count,
        COUNT(*) AS total_payment_count
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    JOIN flc AS fc ON fc.l01 = i.n02
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
monthly_with_avg AS (
    SELECT
        mcd.*,
        AVG(mcd.total_amount) OVER (
            PARTITION BY mcd.customer_id
            ORDER BY mcd.payment_month
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prev_3_month_avg
    FROM monthly_customer_data AS mcd
),
ranked_customers AS (
    SELECT
        mwa.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        RANK() OVER (
            PARTITION BY cnt.c01, mwa.payment_month
            ORDER BY mwa.total_amount DESC
        ) AS country_rank
    FROM monthly_with_avg AS mwa
    JOIN cus AS c ON c.h01 = mwa.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
    WHERE mwa.prev_3_month_avg IS NOT NULL
      AND mwa.total_amount > 3 * mwa.prev_3_month_avg
      AND mwa.staff_count >= 2
      AND mwa.category_count >= 3
)
SELECT
    payment_month,
    country,
    city,
    ROUND(total_amount, 2) AS total_amount,
    payment_count,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(CAST(foreign_store_payment_count AS REAL) / total_payment_count, 4) AS foreign_store_share,
    country_rank
FROM ranked_customers
ORDER BY payment_month, country, country_rank;