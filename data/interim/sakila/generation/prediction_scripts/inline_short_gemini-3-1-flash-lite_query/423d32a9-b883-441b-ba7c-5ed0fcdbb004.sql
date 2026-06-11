WITH monthly_stats AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month,
        SUM(p.p05) AS monthly_sum,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT st.o07) AS store_count
    FROM pay p
    JOIN stf st ON st.o01 = p.p03
    WHERE p.p06 BETWEEN '2005-01-01' AND '2005-12-31 23:59:59'
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
monthly_with_history AS (
    SELECT
        ms.*,
        AVG(ms.monthly_sum) OVER (
            PARTITION BY ms.customer_id
            ORDER BY ms.month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_sum,
        COUNT(*) OVER (
            PARTITION BY ms.customer_id
            ORDER BY ms.month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_months_count
    FROM monthly_stats ms
),
filtered_clients AS (
    SELECT *
    FROM monthly_with_history
    WHERE prev_months_count > 0
      AND monthly_sum >= 2 * prev_avg_sum
      AND payment_count >= 5
      AND (staff_count > 1 OR store_count > 1)
),
ranked_clients AS (
    SELECT
        fc.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        cnt.c01 AS country_id,
        (fc.monthly_sum - fc.prev_avg_sum) AS deviation,
        RANK() OVER (
            PARTITION BY cnt.c01, fc.month
            ORDER BY (fc.monthly_sum - fc.prev_avg_sum) DESC
        ) AS country_rank
    FROM filtered_clients fc
    JOIN cus c ON c.h01 = fc.customer_id
    JOIN adr a ON a.e01 = c.h06
    JOIN cty cty ON cty.d01 = a.e05
    JOIN cnt cnt ON cnt.c01 = cty.d03
)
SELECT
    month,
    country,
    city,
    monthly_sum,
    payment_count,
    ROUND(deviation, 2) AS deviation,
    country_rank
FROM ranked_clients
ORDER BY month, country, country_rank;