WITH payment_base AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p05 AS amount,
        p.p06 AS payment_date,
        date(p.p06, 'start of month') AS month_start,
        p.p03 AS staff_id,
        c.h02 AS home_store_id,
        i.n03 AS issuing_store_id,
        fc.l02 AS category_id,
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        cnt.c01 AS country_id
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    JOIN flc AS fc ON fc.l01 = i.n02
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
monthly_metrics AS (
    SELECT
        customer_id,
        month_start,
        country_name,
        city_name,
        country_id,
        SUM(amount) AS total_amount,
        COUNT(*) AS payment_count,
        MAX(amount) AS max_payment,
        COUNT(DISTINCT staff_id) AS staff_count,
        COUNT(DISTINCT category_id) AS category_count,
        SUM(CASE WHEN home_store_id <> issuing_store_id THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS foreign_store_share
    FROM payment_base
    GROUP BY customer_id, month_start, country_name, city_name, country_id
),
monthly_with_avg AS (
    SELECT
        *,
        AVG(total_amount) OVER (
            PARTITION BY customer_id
            ORDER BY month_start
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prev_3_months_avg
    FROM monthly_metrics
),
ranked_monthly AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY country_id, month_start ORDER BY total_amount DESC) AS country_rank
    FROM monthly_with_avg
    WHERE prev_3_months_avg IS NOT NULL
      AND total_amount > 3 * prev_3_months_avg
      AND staff_count >= 2
      AND category_count >= 3
)
SELECT
    strftime('%Y-%m', month_start) AS month,
    country_name,
    city_name,
    ROUND(total_amount, 2) AS total_amount,
    payment_count,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(foreign_store_share, 4) AS foreign_store_share,
    country_rank
FROM ranked_monthly
ORDER BY month_start, country_id, country_rank;