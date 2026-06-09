WITH payment_enriched AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        p.p05 AS payment_amount,
        date(p.p06, 'start of month') AS month_start,
        c.h02 AS home_store_id,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        COALESCE(inv.n03, -1) AS issuing_store_id,
        cat.c02 AS category_name
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty
        ON cty.d01 = a.e05
    JOIN cnt
        ON cnt.c01 = cty.d03
    JOIN stf AS s
        ON s.o01 = p.p03
    LEFT JOIN ren AS r
        ON r.q01 = p.p04
    LEFT JOIN inv
        ON inv.n01 = r.q03
    LEFT JOIN flc
        ON flc.l01 = inv.n02
    LEFT JOIN cat
        ON cat.g01 = flc.l02
),
monthly_customer_base AS (
    SELECT
        customer_id,
        country_id,
        country_name,
        city_name,
        home_store_id,
        month_start,
        SUM(payment_amount) AS monthly_sum,
        COUNT(*) AS payment_count,
        MAX(payment_amount) AS max_payment,
        COUNT(DISTINCT staff_id) AS distinct_staff_count,
        SUM(CASE WHEN issuing_store_id <> home_store_id THEN 1 ELSE 0 END) AS off_home_store_payment_count,
        1.0 * SUM(CASE WHEN issuing_store_id <> home_store_id THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) AS off_home_store_payment_share,
        COUNT(DISTINCT category_name) AS distinct_category_count
    FROM payment_enriched
    GROUP BY
        customer_id,
        country_id,
        country_name,
        city_name,
        home_store_id,
        month_start
),
monthly_with_prev3_avg AS (
    SELECT
        mcb.*,
        AVG(monthly_sum) OVER (
            PARTITION BY customer_id
            ORDER BY month_start
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prev_3_months_avg
    FROM monthly_customer_base AS mcb
),
ranked AS (
    SELECT
        mw.*,
        RANK() OVER (
            PARTITION BY country_id, month_start
            ORDER BY monthly_sum DESC
        ) AS customer_month_rank_in_country
    FROM monthly_with_prev3_avg AS mw
)
SELECT
    month_start AS month,
    country_name AS country,
    city_name AS city,
    ROUND(monthly_sum, 2) AS month_payments_sum,
    payment_count,
    ROUND(max_payment, 2) AS max_single_payment,
    ROUND(off_home_store_payment_share, 4) AS share_payments_not_in_registration_store,
    customer_month_rank_in_country AS country_month_rank
FROM ranked
WHERE prev_3_months_avg IS NOT NULL
  AND payment_count > 0
  AND distinct_staff_count >= 2
  AND distinct_category_count >= 3
  AND monthly_sum > 3.0 * prev_3_months_avg
ORDER BY
    month_start,
    country_name,
    customer_month_rank_in_country,
    customer_id;