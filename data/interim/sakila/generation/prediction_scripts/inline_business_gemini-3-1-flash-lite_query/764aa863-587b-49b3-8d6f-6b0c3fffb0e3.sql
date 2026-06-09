WITH monthly_customer_data AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS total_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT fc.l02) AS category_count,
        SUM(CASE WHEN stf.o07 <> cus.h02 THEN 1 ELSE 0 END) AS foreign_store_payment_count
    FROM pay AS p
    JOIN cus AS cus ON cus.h01 = p.p02
    JOIN stf AS stf ON stf.o01 = p.p03
    JOIN ren AS ren ON ren.q01 = p.p04
    JOIN inv AS inv ON inv.n01 = ren.q03
    JOIN flc AS fc ON fc.l01 = inv.n02
    GROUP BY p.p02, date(p.p06, 'start of month')
),
rolling_avg AS (
    SELECT
        *,
        AVG(total_amount) OVER (
            PARTITION BY customer_id
            ORDER BY month_start
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prev_3_month_avg
    FROM monthly_customer_data
),
country_ranks AS (
    SELECT
        ra.*,
        cus.h03 || ' ' || cus.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        RANK() OVER (
            PARTITION BY cnt.c01, ra.month_start
            ORDER BY ra.total_amount DESC
        ) AS country_rank
    FROM rolling_avg AS ra
    JOIN cus ON cus.h01 = ra.customer_id
    JOIN adr ON adr.e01 = cus.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
)
SELECT
    strftime('%Y-%m', month_start) AS month,
    country,
    city,
    ROUND(total_amount, 2) AS total_amount,
    payment_count,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(CAST(foreign_store_payment_count AS REAL) / payment_count, 4) AS foreign_store_share,
    country_rank
FROM country_ranks
WHERE prev_3_month_avg IS NOT NULL
  AND total_amount > 3 * prev_3_month_avg
  AND staff_count >= 2
  AND category_count >= 3
ORDER BY month, country, country_rank;