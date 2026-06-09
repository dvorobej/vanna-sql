WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS total_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT i.n03) AS store_count,
        SUM(CASE WHEN i.n03 <> c.h02 THEN 1 ELSE 0 END) AS foreign_store_payments,
        COUNT(DISTINCT fc.l02) AS category_count
    FROM pay AS p
    JOIN cus AS c ON p.p02 = c.h01
    JOIN ren AS r ON p.p04 = r.q01
    JOIN inv AS i ON r.q03 = i.n01
    JOIN flc AS fc ON i.n02 = fc.l01
    GROUP BY p.p02, date(p.p06, 'start of month')
),
monthly_with_history AS (
    SELECT
        mp.*,
        AVG(mp.total_amount) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.month_start
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS avg_prev_3_months
    FROM monthly_payments AS mp
),
filtered_customers AS (
    SELECT *
    FROM monthly_with_history
    WHERE total_amount > 3 * avg_prev_3_months
      AND staff_count >= 2
      AND category_count >= 3
),
ranked_customers AS (
    SELECT
        fc.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cty.d02 AS city,
        cnt.c02 AS country,
        RANK() OVER (
            PARTITION BY cnt.c01, fc.month_start
            ORDER BY fc.total_amount DESC
        ) AS country_rank
    FROM filtered_customers AS fc
    JOIN cus AS c ON fc.customer_id = c.h01
    JOIN adr AS a ON c.h06 = a.e01
    JOIN cty ON a.e05 = cty.d01
    JOIN cnt ON cty.d03 = cnt.c01
)
SELECT
    month_start,
    customer_name,
    country,
    city,
    total_amount,
    payment_count,
    max_payment,
    ROUND(CAST(foreign_store_payments AS REAL) / payment_count, 4) AS foreign_store_share,
    country_rank
FROM ranked_customers
ORDER BY month_start, country, country_rank;