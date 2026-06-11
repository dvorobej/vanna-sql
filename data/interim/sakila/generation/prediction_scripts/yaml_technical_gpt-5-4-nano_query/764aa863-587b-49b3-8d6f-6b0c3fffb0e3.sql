WITH payment_base AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        p.p05 AS payment_amount,
        p.p06 AS payment_datetime,
        date(p.p06, 'start of month') AS month_start,
        c.h02 AS customer_home_store_id,
        ct.d01 AS city_id,
        ct.d02 AS city_name,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        CASE
            WHEN c.h02 <> inv.n03 THEN 1
            ELSE 0
        END AS is_not_home_store_payment,
        cat.g01 AS category_id
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ct
        ON ct.d01 = a.e05
    JOIN cnt AS cnt
        ON cnt.c01 = ct.d03
    JOIN ren AS r
        ON r.q01 = p.p04
    JOIN inv AS inv
        ON inv.n01 = r.q03
    JOIN flm AS f
        ON f.i01 = inv.n02
    LEFT JOIN flc AS fc
        ON fc.l01 = f.i01
    LEFT JOIN cat
        ON cat.g01 = fc.l02
),
customer_month AS (
    SELECT
        customer_id,
        month_start,
        country_name,
        city_name,
        MAX(country_id) AS country_id,
        MAX(customer_home_store_id) AS customer_home_store_id,
        COUNT(*) AS payment_count,
        SUM(payment_amount) AS month_amount,
        MAX(payment_amount) AS max_payment_amount,
        COUNT(DISTINCT staff_id) AS distinct_staff_count,
        SUM(is_not_home_store_payment) AS not_home_store_payment_count,
        1.0 * SUM(is_not_home_store_payment) / COUNT(*) AS not_home_store_payment_share,
        COUNT(DISTINCT category_id) AS distinct_categories_count
    FROM payment_base
    GROUP BY
        customer_id,
        month_start,
        country_name,
        city_name
),
customer_month_with_prev AS (
    SELECT
        cm.*,
        AVG(cm.month_amount) OVER (
            PARTITION BY cm.customer_id
            ORDER BY cm.month_start
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prev_3_months_avg_amount
    FROM customer_month AS cm
),
filtered AS (
    SELECT *
    FROM customer_month_with_prev
    WHERE prev_3_months_avg_amount IS NOT NULL
      AND month_amount > 3.0 * prev_3_months_avg_amount
      AND distinct_staff_count >= 2
      AND distinct_categories_count >= 3
),
ranked AS (
    SELECT
        f.*,
        RANK() OVER (
            PARTITION BY f.country_id, f.month_start
            ORDER BY f.month_amount DESC
        ) AS country_month_customer_rank
    FROM filtered AS f
)
SELECT
    r.month_start AS payment_month,
    r.country_name AS country,
    r.city_name AS city,
    ROUND(r.month_amount, 2) AS month_amount,
    r.payment_count,
    ROUND(r.max_payment_amount, 2) AS max_payment_amount,
    ROUND(r.not_home_store_payment_share, 4) AS not_home_store_payment_share,
    r.country_month_customer_rank
FROM ranked AS r
ORDER BY
    r.month_start,
    r.country_name,
    r.country_month_customer_rank,
    r.customer_id;