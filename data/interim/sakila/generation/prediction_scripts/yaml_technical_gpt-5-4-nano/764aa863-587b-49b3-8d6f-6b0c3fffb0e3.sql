WITH monthly_payments AS (
    SELECT
        c.h01 AS customer_id,
        c.h02 AS customer_store_id,
        c.h06 AS customer_address_id,
        city.d02 AS city_name,
        cnt.c02 AS country_name,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS month_amount,
        COUNT(*) AS payment_count,
        MAX(p.p05) AS max_single_payment,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        SUM(CASE WHEN s.o07 <> c.h02 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS off_registration_store_payment_share
    FROM cus AS c
    JOIN pay AS p
        ON c.h01 = p.p02
    JOIN ren AS r
        ON p.p04 = r.q01
    JOIN inv AS i
        ON r.q03 = i.n01
    JOIN flm AS f
        ON i.n02 = f.i01
    JOIN flc AS fc
        ON f.i01 = fc.l01
    JOIN cat AS ct
        ON fc.l02 = ct.g01
    JOIN sto AS s
        ON c.h02 = s.j01
    JOIN adr AS a
        ON c.h06 = a.e01
    JOIN cty AS city
        ON a.e05 = city.d01
    JOIN cnt AS cnt
        ON city.d03 = cnt.c01
    WHERE p.p04 IS NOT NULL
      AND f.i01 IS NOT NULL
      AND ct.g01 IS NOT NULL
    GROUP BY
        c.h01,
        c.h02,
        c.h06,
        city.d02,
        cnt.c02,
        date(p.p06, 'start of month')
),
monthly_with_prev_avg AS (
    SELECT
        mp.*,
        AVG(mp.month_amount) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.month_start
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS avg_prev_3_months_amount
    FROM monthly_payments AS mp
),
eligible_customers_months AS (
    SELECT
        mpa.*
    FROM monthly_with_prev_avg AS mpa
    WHERE mpa.avg_prev_3_months_amount IS NOT NULL
      AND mpa.month_amount > 3.0 * mpa.avg_prev_3_months_amount
      AND mpa.distinct_staff_count >= 2
),
customer_month_category_counts AS (
    SELECT
        c.h01 AS customer_id,
        city.d02 AS city_name,
        cnt.c02 AS country_name,
        date(p.p06, 'start of month') AS month_start,
        COUNT(DISTINCT fc.l02) AS category_count_g01
    FROM cus AS c
    JOIN pay AS p
        ON c.h01 = p.p02
    JOIN ren AS r
        ON p.p04 = r.q01
    JOIN inv AS i
        ON r.q03 = i.n01
    JOIN flm AS f
        ON i.n02 = f.i01
    JOIN flc AS fc
        ON f.i01 = fc.l01
    JOIN adr AS a
        ON c.h06 = a.e01
    JOIN cty AS city
        ON a.e05 = city.d01
    JOIN cnt AS cnt
        ON city.d03 = cnt.c01
    GROUP BY
        c.h01,
        city.d02,
        cnt.c02,
        date(p.p06, 'start of month')
),
filtered AS (
    SELECT
        e.*
    FROM eligible_customers_months AS e
    JOIN customer_month_category_counts AS cmcc
      ON cmcc.customer_id = e.customer_id
     AND cmcc.month_start = e.month_start
     AND cmcc.country_name = e.country_name
     AND cmcc.city_name = e.city_name
    WHERE cmcc.category_count_g01 >= 3
),
ranked_customers AS (
    SELECT
        f.*,
        RANK() OVER (
            PARTITION BY f.country_name, f.month_start
            ORDER BY f.month_amount DESC
        ) AS customer_rank_in_country
    FROM filtered AS f
)
SELECT
    month_start AS month,
    country_name AS c02,
    city_name AS d02,
    ROUND(SUM(month_amount), 2) AS total_month_amount,
    SUM(payment_count) AS total_payment_count,
    MAX(max_single_payment) AS max_single_payment,
    ROUND(AVG(off_registration_store_payment_share), 4) AS off_registration_store_payment_share,
    customer_rank_in_country
FROM ranked_customers
GROUP BY
    month_start,
    country_name,
    city_name,
    customer_rank_in_country
ORDER BY
    month_start,
    c02,
    d02,
    total_month_amount DESC;