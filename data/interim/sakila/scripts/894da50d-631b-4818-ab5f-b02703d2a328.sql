WITH
payment_base AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        c.h03 AS customer_first_name,
        c.h04 AS customer_last_name,
        p.p05 AS amount,
        p.p06 AS payment_date,
        date(p.p06, 'start of month') AS month_start,
        p.p03 AS staff_id,
        sf.o07 AS staff_store_id,
        r.q01 AS rental_id,
        r.q03 AS inventory_id,
        i.n02 AS film_id,
        i.n03 AS issuing_store_id,
        cust_city.d01 AS customer_city_id,
        cust_city.d03 AS customer_country_id,
        store_city.d01 AS issuing_store_city_id,
        store_city.d03 AS issuing_store_country_id,
        CASE
            WHEN cust_city.d01 <> store_city.d01
              OR cust_city.d03 <> store_city.d03
            THEN 1
            ELSE 0
        END AS is_foreign_store_payment
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN ren AS r
        ON r.q01 = p.p04
    JOIN inv AS i
        ON i.n01 = r.q03
    JOIN stf AS sf
        ON sf.o01 = p.p03
    JOIN adr AS cust_addr
        ON cust_addr.e01 = c.h06
    JOIN cty AS cust_city
        ON cust_city.d01 = cust_addr.e05
    JOIN sto AS issuing_store
        ON issuing_store.j01 = i.n03
    JOIN adr AS store_addr
        ON store_addr.e01 = issuing_store.j03
    JOIN cty AS store_city
        ON store_city.d01 = store_addr.e05
),
monthly_metrics AS (
    SELECT
        customer_id,
        customer_first_name,
        customer_last_name,
        month_start,
        SUM(amount) AS total_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT staff_store_id) AS staff_store_count,
        SUM(is_foreign_store_payment) AS foreign_payment_count,
        1.0 * SUM(is_foreign_store_payment) / COUNT(*) AS foreign_payment_share,
        MAX(amount) AS largest_payment
    FROM payment_base
    GROUP BY
        customer_id,
        customer_first_name,
        customer_last_name,
        month_start
),
monthly_with_windows AS (
    SELECT
        mm.*,
        AVG(total_amount) OVER (
            PARTITION BY customer_id
            ORDER BY month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS previous_months_avg_amount,
        RANK() OVER (
            PARTITION BY customer_id
            ORDER BY total_amount DESC
        ) AS month_amount_rank
    FROM monthly_metrics AS mm
),
qualifying_months AS (
    SELECT
        *
    FROM monthly_with_windows
    WHERE previous_months_avg_amount IS NOT NULL
      AND total_amount > 3 * previous_months_avg_amount
      AND payment_count >= 5
      AND staff_store_count >= 2
      AND foreign_payment_count > 0
),
film_category_counts AS (
    SELECT
        l01 AS film_id,
        COUNT(*) AS category_count
    FROM flc
    GROUP BY l01
),
category_sums AS (
    SELECT
        pb.customer_id,
        pb.month_start,
        cat.g02 AS category_name,
        SUM(pb.amount * 1.0 / fcc.category_count) AS category_amount
    FROM payment_base AS pb
    JOIN qualifying_months AS qm
        ON qm.customer_id = pb.customer_id
       AND qm.month_start = pb.month_start
    JOIN film_category_counts AS fcc
        ON fcc.film_id = pb.film_id
    JOIN flc AS fc
        ON fc.l01 = pb.film_id
    JOIN cat
        ON cat.g01 = fc.l02
    GROUP BY
        pb.customer_id,
        pb.month_start,
        cat.g02
),
category_ranked AS (
    SELECT
        cs.*,
        qm.total_amount,
        SUM(cs.category_amount) OVER (
            PARTITION BY cs.customer_id, cs.month_start
            ORDER BY cs.category_amount DESC, cs.category_name
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS previous_categories_amount
    FROM category_sums AS cs
    JOIN qualifying_months AS qm
        ON qm.customer_id = cs.customer_id
       AND qm.month_start = cs.month_start
),
major_category_rows AS (
    SELECT
        customer_id,
        month_start,
        category_name,
        category_amount,
        category_name || ' (' || printf('%.2f', category_amount) || ')' AS category_label
    FROM category_ranked
    WHERE COALESCE(previous_categories_amount, 0) < total_amount * 0.5
),
major_categories AS (
    SELECT
        customer_id,
        month_start,
        group_concat(category_label, ', ') AS major_categories
    FROM (
        SELECT
            customer_id,
            month_start,
            category_label
        FROM major_category_rows
        ORDER BY
            customer_id,
            month_start,
            category_amount DESC,
            category_name
    )
    GROUP BY
        customer_id,
        month_start
)
SELECT
    qm.customer_id,
    qm.customer_first_name,
    qm.customer_last_name,
    strftime('%Y-%m', qm.month_start) AS payment_month,
    ROUND(qm.total_amount, 2) AS total_amount,
    qm.payment_count,
    ROUND(qm.foreign_payment_share, 4) AS foreign_store_payment_share,
    ROUND(qm.largest_payment, 2) AS largest_payment,
    qm.month_amount_rank,
    COALESCE(mc.major_categories, '') AS major_categories
FROM qualifying_months AS qm
LEFT JOIN major_categories AS mc
    ON mc.customer_id = qm.customer_id
   AND mc.month_start = qm.month_start
ORDER BY
    qm.customer_id,
    qm.month_start;