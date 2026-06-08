WITH payment_enriched AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        date(p.p06) AS payment_date,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p03 AS staff_id,
        s.o07 AS store_id,
        customer_country.c01 AS customer_country_id,
        customer_country.c02 AS customer_country,
        store_country.c01 AS store_country_id,
        store_country.c02 AS store_country
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS customer_address
        ON customer_address.e01 = c.h06
    JOIN cty AS customer_city
        ON customer_city.d01 = customer_address.e05
    JOIN cnt AS customer_country
        ON customer_country.c01 = customer_city.d03
    JOIN stf AS s
        ON s.o01 = p.p03
    JOIN sto AS store
        ON store.j01 = s.o07
    JOIN adr AS store_address
        ON store_address.e01 = store.j03
    JOIN cty AS store_city
        ON store_city.d01 = store_address.e05
    JOIN cnt AS store_country
        ON store_country.c01 = store_city.d03
    WHERE p.p06 >= '2004-12-02'
      AND p.p06 < '2006-01-01'
),
customer_day_totals AS (
    SELECT
        customer_id,
        payment_date,
        SUM(payment_amount) AS day_amount
    FROM payment_enriched
    GROUP BY
        customer_id,
        payment_date
),
daily_activity AS (
    SELECT
        customer_id,
        customer_name,
        customer_country_id,
        customer_country,
        payment_date,
        COUNT(*) AS payment_count,
        SUM(payment_amount) AS daily_payment_amount,
        COUNT(DISTINCT staff_id) AS staff_count,
        COUNT(DISTINCT store_id) AS store_count,
        GROUP_CONCAT(DISTINCT store_country) AS store_countries,
        MAX(CASE WHEN store_country_id <> customer_country_id THEN 1 ELSE 0 END) AS has_foreign_store_payment
    FROM payment_enriched
    WHERE payment_date >= '2005-01-01'
      AND payment_date < '2006-01-01'
    GROUP BY
        customer_id,
        customer_name,
        customer_country_id,
        customer_country,
        payment_date
),
daily_with_history AS (
    SELECT
        d.*,
        (
            SELECT AVG(h.day_amount)
            FROM customer_day_totals AS h
            WHERE h.customer_id = d.customer_id
              AND h.payment_date >= date(d.payment_date, '-30 days')
              AND h.payment_date < d.payment_date
        ) AS avg_prev_30_day_amount
    FROM daily_activity AS d
),
suspicious_days AS (
    SELECT
        *,
        daily_payment_amount - avg_prev_30_day_amount AS excess_amount
    FROM daily_with_history
    WHERE payment_count >= 3
      AND store_count >= 2
      AND has_foreign_store_payment = 1
      AND avg_prev_30_day_amount IS NOT NULL
      AND daily_payment_amount >= 2.0 * avg_prev_30_day_amount
)
SELECT
    customer_id,
    customer_name,
    payment_date,
    customer_country,
    payment_count,
    ROUND(daily_payment_amount, 2) AS daily_payment_amount,
    ROUND(avg_prev_30_day_amount, 2) AS avg_prev_30_day_amount,
    staff_count,
    store_count,
    store_countries,
    RANK() OVER (
        PARTITION BY customer_country_id
        ORDER BY excess_amount DESC
    ) AS suspicion_rank
FROM suspicious_days
ORDER BY
    customer_country,
    suspicion_rank,
    customer_id,
    payment_date;