WITH payment_base AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        p.p04 AS rental_id,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p06 AS payment_date,
        date(p.p06, 'start of month') AS month_start,
        c.h02 AS home_store_id,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        ct.d01 AS city_id,
        ct.d02 AS city_name,
        i.n01 AS inventory_id,
        i.n02 AS film_id
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ct
        ON ct.d01 = a.e05
    JOIN cnt AS cnt
        ON cnt.c01 = ct.d03
    LEFT JOIN ren AS r
        ON r.q01 = p.p04
    LEFT JOIN inv AS i
        ON i.n01 = r.q03
),
monthly_customer_stats AS (
    SELECT
        pb.customer_id,
        pb.country_id,
        pb.country_name,
        pb.city_id,
        pb.city_name,
        pb.month_start,
        SUM(pb.payment_amount) AS month_total_amount,
        COUNT(*) AS payment_count,
        MAX(pb.payment_amount) AS max_payment_amount,
        COUNT(DISTINCT pb.staff_id) AS distinct_staff_count,
        COUNT(DISTINCT CASE WHEN i.n03 IS NULL THEN NULL ELSE i.n03 END) AS distinct_rental_store_count,
        SUM(CASE WHEN pb.home_store_id <> i.n03 THEN 1 ELSE 0 END) AS non_home_store_payments_count,
        COUNT(*) AS all_payments_count
    FROM payment_base AS pb
    LEFT JOIN ren AS r
        ON r.q01 = pb.rental_id
    LEFT JOIN inv AS i
        ON i.n01 = r.q03
    GROUP BY
        pb.customer_id,
        pb.country_id,
        pb.country_name,
        pb.city_id,
        pb.city_name,
        pb.month_start
),
monthly_with_prev3_avg AS (
    SELECT
        mcs.*,
        AVG(mcs.month_total_amount) OVER (
            PARTITION BY mcs.customer_id
            ORDER BY mcs.month_start
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prev3_months_avg_amount
    FROM monthly_customer_stats AS mcs
),
monthly_with_categories AS (
    SELECT
        pb.customer_id,
        pb.month_start,
        COUNT(DISTINCT flc.l02) AS distinct_film_categories_count
    FROM payment_base AS pb
    JOIN ren AS r
        ON r.q01 = pb.rental_id
    JOIN inv AS i
        ON i.n01 = r.q03
    JOIN flc
        ON flc.l01 = i.n01
    GROUP BY
        pb.customer_id,
        pb.month_start
),
qualifying AS (
    SELECT
        mwp.customer_id,
        mwp.country_id,
        mwp.country_name,
        mwp.city_id,
        mwp.city_name,
        mwp.month_start,
        mwp.month_total_amount,
        mwp.payment_count,
        mwp.max_payment_amount,
        mwp.distinct_staff_count,
        mwp.non_home_store_payments_count,
        mwp.all_payments_count,
        mwp.prev3_months_avg_amount,
        mc.distinct_film_categories_count
    FROM monthly_with_prev3_avg AS mwp
    JOIN monthly_with_categories AS mc
        ON mc.customer_id = mwp.customer_id
       AND mc.month_start = mwp.month_start
    WHERE mwp.prev3_months_avg_amount IS NOT NULL
      AND mwp.month_total_amount > 3.0 * mwp.prev3_months_avg_amount
      AND mwp.distinct_staff_count >= 2
      AND mc.distinct_film_categories_count >= 3
),
ranked AS (
    SELECT
        q.*,
        RANK() OVER (
            PARTITION BY q.country_id, q.month_start
            ORDER BY q.month_total_amount DESC
        ) AS customer_country_month_rank
    FROM qualifying AS q
)
SELECT
    ranked.month_start AS month,
    ranked.country_name AS country,
    ranked.city_name AS city,
    ROUND(ranked.month_total_amount, 2) AS payment_sum,
    ranked.payment_count,
    ROUND(ranked.max_payment_amount, 2) AS max_payment,
    ROUND(
        1.0 * ranked.non_home_store_payments_count / NULLIF(ranked.all_payments_count, 0),
        4
    ) AS non_home_store_payment_share,
    ranked.customer_country_month_rank
FROM ranked
ORDER BY
    ranked.month_start,
    ranked.country_name,
    ranked.customer_country_month_rank,
    ranked.customer_id;