WITH monthly_base AS (
    SELECT
        c.h01 AS customer_id,
        cn.c02 AS country_name,
        ct.d02 AS city_name,
        c.h02 AS customer_store_id,
        date(p.p06, 'start of month') AS month_start,
        p.p01 AS payment_id,
        p.p05 AS payment_amount,
        p.p03 AS staff_id,
        r.q01 AS rental_id,
        i.n01 AS inventory_id,
        f.i01 AS film_id,
        fca.l02 AS category_id,
        i.n03 AS issuing_store_id,
        CASE WHEN i.n03 <> c.h02 THEN 1 ELSE 0 END AS is_foreign_store_payment
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN ren AS r
        ON r.q01 = p.p04
    JOIN inv AS i
        ON i.n01 = r.q03
    JOIN flm AS f
        ON f.i01 = i.n02
    JOIN flc AS fca
        ON fca.l01 = f.i01
    JOIN cat
        ON cat.g01 = fca.l02
    JOIN sto AS s_reg
        ON s_reg.j01 = c.h02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ct
        ON ct.d01 = a.e05
    JOIN cnt AS cn
        ON cn.c01 = ct.d03
    WHERE p.p06 IS NOT NULL
),
monthly_customer AS (
    SELECT
        customer_id,
        month_start,
        country_name,
        city_name,
        customer_store_id,
        SUM(payment_amount) AS month_payment_sum,
        COUNT(*) AS payment_count,
        MAX(payment_amount) AS max_single_payment,
        SUM(is_foreign_store_payment) * 1.0 / NULLIF(COUNT(*), 0) AS foreign_store_payment_share,
        COUNT(DISTINCT staff_id) AS staff_count,
        COUNT(DISTINCT category_id) AS distinct_category_count
    FROM monthly_base
    GROUP BY
        customer_id, month_start, country_name, city_name, customer_store_id
),
monthly_with_prev AS (
    SELECT
        mc.*,
        AVG(month_payment_sum) OVER (
            PARTITION BY customer_id
            ORDER BY month_start
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prev_3_month_avg_sum
    FROM monthly_customer AS mc
),
qualified_months AS (
    SELECT
        *
    FROM monthly_with_prev
    WHERE prev_3_month_avg_sum IS NOT NULL
      AND prev_3_month_avg_sum > 0
      AND month_payment_sum > prev_3_month_avg_sum * 3.0
      AND staff_count >= 2
      AND distinct_category_count >= 3
),
ranked AS (
    SELECT
        qm.*,
        RANK() OVER (
            PARTITION BY country_name, month_start
            ORDER BY month_payment_sum DESC
        ) AS customer_rank_in_country_month
    FROM qualified_months AS qm
)
SELECT
    country_name AS c02,
    city_name AS d02,
    month_start AS month,
    customer_id AS h01,
    ROUND(month_payment_sum, 2) AS month_payment_sum,
    payment_count,
    ROUND(max_single_payment, 2) AS max_single_payment,
    ROUND(foreign_store_payment_share, 4) AS foreign_store_payment_share,
    customer_rank_in_country_month AS customer_rank
FROM ranked
ORDER BY
    c02,
    month,
    d02,
    customer_rank_in_country_month,
    month_payment_sum DESC,
    h01;