WITH payment_base AS (
    SELECT
        p.p02 AS customer_id,
        p.p06 AS payment_datetime,
        date(p.p06, 'start of month') AS month_start,
        CAST(p.p05 AS REAL) AS amount,
        p.p01 AS payment_id,
        p.p03 AS staff_id,
        s.o07 AS staff_store_id,
        cu.h06 AS customer_address_id,
        i.n03 AS rental_store_id,
        r.q01 AS rental_id,
        f.i01 AS film_id
    FROM pay AS p
    JOIN cus AS cu
        ON cu.h01 = p.p02
    LEFT JOIN ren AS r
        ON r.q01 = p.p04
    LEFT JOIN inv AS i
        ON i.n01 = r.q03
    LEFT JOIN flm AS f
        ON f.i01 = i.n02
    LEFT JOIN stf AS s
        ON s.o01 = p.p03
),
payment_enriched AS (
    SELECT
        pb.customer_id,
        pb.month_start,
        pb.amount,
        pb.payment_id,
        pb.staff_id,
        pb.staff_store_id,
        pb.film_id,

        cust_city.d02 AS city_name,
        cust_country.c02 AS country_name,
        cust_country.c01 AS country_id,

        CASE WHEN pb.staff_store_id <> cu_store.j01 THEN 1 ELSE 0 END AS is_off_home_store_payment
    FROM payment_base AS pb
    JOIN cus AS c
        ON c.h01 = pb.customer_id
    JOIN adr AS cust_addr
        ON cust_addr.e01 = c.h06
    JOIN cty AS cust_city
        ON cust_city.d01 = cust_addr.e05
    JOIN cnt AS cust_country
        ON cust_country.c01 = cust_city.d03
    JOIN sto AS cu_store
        ON cu_store.j01 = c.h02
),
monthly_payments AS (
    SELECT
        pe.customer_id,
        pe.country_id,
        pe.country_name,
        pe.city_name,
        pe.month_start,

        COUNT(*) AS payment_count,
        SUM(pe.amount) AS month_amount,
        MAX(pe.amount) AS max_payment,
        COUNT(DISTINCT pe.staff_id) AS distinct_staff_count,
        SUM(pe.is_off_home_store_payment) * 1.0 / COUNT(*) AS off_home_store_payment_share
    FROM payment_enriched AS pe
    GROUP BY
        pe.customer_id,
        pe.country_id,
        pe.country_name,
        pe.city_name,
        pe.month_start
),
previous_avg AS (
    SELECT
        mp.*,
        AVG(mp.month_amount) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.month_start
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prev_3_month_avg_amount
    FROM monthly_payments AS mp
),
monthly_categories AS (
    SELECT
        pb.customer_id,
        date(pb.payment_datetime, 'start of month') AS month_start,
        COUNT(DISTINCT fc.l02) AS distinct_category_count
    FROM payment_base AS pb
    LEFT JOIN flc AS fc
        ON fc.l01 = pb.film_id
    GROUP BY
        pb.customer_id,
        date(pb.payment_datetime, 'start of month')
),
qualified AS (
    SELECT
        pa.*,
        mc.distinct_category_count
    FROM previous_avg AS pa
    JOIN monthly_categories AS mc
        ON mc.customer_id = pa.customer_id
       AND mc.month_start = pa.month_start
    WHERE
        pa.prev_3_month_avg_amount IS NOT NULL
        AND pa.month_amount > 3.0 * pa.prev_3_month_avg_amount
        AND pa.distinct_staff_count >= 2
        AND mc.distinct_category_count >= 3
)
SELECT
    q.month_start AS month,
    q.country_name AS country,
    q.city_name AS city,
    ROUND(q.month_amount, 2) AS month_payments_sum,
    q.payment_count,
    ROUND(q.max_payment, 2) AS max_payment,
    ROUND(q.off_home_store_payment_share, 4) AS off_home_store_payment_share,
    RANK() OVER (
        PARTITION BY q.country_id, q.month_start
        ORDER BY q.month_amount DESC
    ) AS country_month_amount_rank
FROM qualified AS q
ORDER BY
    q.country_name,
    q.month_start,
    country_month_amount_rank,
    q.customer_id;