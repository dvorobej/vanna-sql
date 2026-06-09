WITH monthly AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS monthly_amount
    FROM pay AS p
    WHERE p.p06 IS NOT NULL
    GROUP BY
        p.p02,
        date(p.p06, 'start of month')
),
monthly_with_history AS (
    SELECT
        m.*,
        AVG(m.monthly_amount) OVER (
            PARTITION BY m.customer_id
            ORDER BY m.month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS personal_avg_amount
    FROM monthly AS m
),
customer_month AS (
    SELECT
        mwh.*,
        c.h06 AS customer_address_id,
        c.h01 AS customer_id_check,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name
    FROM monthly_with_history AS mwh
    JOIN cus AS c
        ON c.h01 = mwh.customer_id
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ct
        ON ct.d01 = a.e05
    JOIN cnt
        ON cnt.c01 = ct.d03
),
country_month_paycounts AS (
    SELECT
        customer_id,
        month_start,
        country_id,
        payment_count,
        monthly_amount,
        personal_avg_amount,
        country_name,
        COUNT(*) OVER (PARTITION BY country_id, month_start) AS country_customer_count,
        ROW_NUMBER() OVER (
            PARTITION BY country_id, month_start
            ORDER BY payment_count
        ) AS paycount_rank_asc
    FROM customer_month
),
country_month_median_threshold AS (
    SELECT
        country_id,
        month_start,
        MAX(
            CASE
                WHEN paycount_rank_asc = CAST((country_customer_count + 1) / 2 AS INTEGER)
                THEN payment_count
            END
        ) AS median_payment_count
    FROM country_month_paycounts
    GROUP BY country_id, month_start
),
qualified AS (
    SELECT
        cmp.*
    FROM country_month_paycounts AS cmp
    JOIN country_month_median_threshold AS mt
        ON mt.country_id = cmp.country_id
       AND mt.month_start = cmp.month_start
    WHERE cmp.personal_avg_amount IS NOT NULL
      AND cmp.monthly_amount > 3.0 * cmp.personal_avg_amount
      AND cmp.payment_count > mt.median_payment_count
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        c.h02 AS home_store_id,
        cnt.c02 AS country_name,
        ct.d02 AS city_name,
        cty_home.d02 AS customer_city_name,
        cty_home_country.c02 AS customer_country_name,
        a.e05 AS customer_city_id,
        cty_home_country.c01 AS customer_country_id,
        (SELECT j01 FROM sto WHERE sto.j01 = c.h02) AS dummy
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ct
        ON ct.d01 = a.e05
    JOIN cnt AS cty_home_country
        ON cty_home_country.c01 = ct.d03
    LEFT JOIN cty AS cty_home
        ON cty_home.d01 = a.e05
),
qualified_payments AS (
    SELECT
        q.customer_id,
        q.month_start,
        p.p01 AS payment_id,
        p.p05 AS payment_amount,
        p.p04 AS rental_id,
        p.p03 AS staff_id
    FROM qualified AS q
    JOIN pay AS p
        ON p.p02 = q.customer_id
       AND date(p.p06, 'start of month') = q.month_start
),
payment_movie_categories AS (
    SELECT
        qp.customer_id,
        qp.month_start,
        COUNT(*) AS total_payments,
        SUM(CASE
            WHEN cat.g02 IN ('Action','New') THEN 1
            ELSE 0
        END) AS action_new_payments
    FROM qualified_payments qp
    JOIN ren AS r
        ON r.q01 = qp.rental_id
    JOIN inv AS n
        ON n.n01 = r.q03
    JOIN flm AS f
        ON f.i01 = n.n02
    JOIN flc AS fc
        ON fc.l01 = f.i01
    JOIN cat
        ON cat.g01 = fc.l02
    GROUP BY qp.customer_id, qp.month_start
)
SELECT
    q.month_start AS month,
    q.customer_id,
    c.h03 AS h03,
    c.h04 AS h04,
    q.country_name,
    q.payment_count AS payment_count,
    q.monthly_amount AS total_payment_amount,
    MAX(pp.payment_amount) AS max_single_payment_amount,
    (pmc.action_new_payments * 1.0 / NULLIF(pmc.total_payments,0)) AS action_new_payments_share
FROM qualified AS q
JOIN cus AS c
    ON c.h01 = q.customer_id
JOIN qualified_payments AS pp
    ON pp.customer_id = q.customer_id
   AND pp.month_start = q.month_start
JOIN payment_movie_categories AS pmc
    ON pmc.customer_id = q.customer_id
   AND pmc.month_start = q.month_start
GROUP BY
    q.month_start,
    q.customer_id,
    c.h03,
    c.h04,
    q.country_name,
    q.payment_count,
    q.monthly_amount,
    pmc.action_new_payments_share
ORDER BY
    q.country_name,
    q.month_start,
    total_payment_amount DESC,
    q.customer_id;