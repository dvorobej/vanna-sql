WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT fc.l02) AS category_count,
        SUM(CASE WHEN i.n03 <> c.h02 THEN 1 ELSE 0 END) AS foreign_store_payment_count
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    JOIN flc AS fc ON fc.l01 = i.n02
    GROUP BY p.p02, date(p.p06, 'start of month')
),
monthly_with_history AS (
    SELECT
        *,
        AVG(monthly_amount) OVER (
            PARTITION BY customer_id
            ORDER BY month_start
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prev_3_month_avg,
        COUNT(*) OVER (
            PARTITION BY customer_id
            ORDER BY month_start
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS history_count
    FROM monthly_customer_stats
),
filtered_customers AS (
    SELECT
        m.*,
        c.h06 AS address_id
    FROM monthly_with_history AS m
    JOIN cus AS c ON c.h01 = m.customer_id
    WHERE history_count = 3
      AND monthly_amount > 3 * prev_3_month_avg
      AND staff_count >= 2
      AND category_count >= 3
),
ranked_customers AS (
    SELECT
        f.*,
        cty.d02 AS city,
        cnt.c02 AS country,
        RANK() OVER (
            PARTITION BY cnt.c01, f.month_start
            ORDER BY f.monthly_amount DESC
        ) AS country_rank
    FROM filtered_customers AS f
    JOIN adr ON adr.e01 = f.address_id
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
)
SELECT
    strftime('%Y-%m', month_start) AS month,
    country,
    city,
    ROUND(monthly_amount, 2) AS total_amount,
    payment_count,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(CAST(foreign_store_payment_count AS REAL) / payment_count, 4) AS foreign_store_share,
    country_rank
FROM ranked_customers
ORDER BY month, country, country_rank;