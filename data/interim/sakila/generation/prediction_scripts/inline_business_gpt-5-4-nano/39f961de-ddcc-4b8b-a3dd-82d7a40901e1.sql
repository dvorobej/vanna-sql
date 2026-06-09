WITH payment_enriched AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        c.h03 AS customer_first_name,
        c.h04 AS customer_last_name,
        p.p05 AS payment_amount,
        date(p.p06) AS payment_date,
        p.p03 AS staff_id,
        st.o07 AS staff_store_id,
        cu_city.d02 AS city,
        cu_country.c02 AS country,
        CASE
            WHEN f.i11 IN ('R','NC-17') THEN 1
            ELSE 0
        END AS is_r_or_nc17
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS cust_addr
        ON cust_addr.e01 = c.h06
    JOIN cty AS cu_city
        ON cu_city.d01 = cust_addr.e05
    JOIN cnt AS cu_country
        ON cu_country.c01 = cu_city.d03
    JOIN stf AS st
        ON st.o01 = p.p03
    JOIN ren AS r
        ON r.q01 = p.p04
    JOIN inv AS i
        ON i.n01 = r.q03
    JOIN flm AS f
        ON f.i01 = i.n02
    WHERE p.p06 IS NOT NULL
),
daily_customer AS (
    SELECT
        customer_id,
        customer_first_name,
        customer_last_name,
        city,
        country,
        payment_date,
        COUNT(*) AS payment_count,
        SUM(payment_amount) AS daily_payment_sum,
        MAX(payment_amount) AS max_payment,
        COUNT(DISTINCT staff_id) AS staff_count,
        COUNT(DISTINCT staff_store_id) AS store_count,
        SUM(CASE WHEN is_r_or_nc17 = 1 THEN payment_amount ELSE 0 END) AS r_or_nc17_payment_sum
    FROM payment_enriched
    GROUP BY
        customer_id,
        customer_first_name,
        customer_last_name,
        city,
        country,
        payment_date
),
daily_with_history AS (
    SELECT
        dc.*,
        (
            SELECT AVG(dch.daily_payment_sum)
            FROM daily_customer AS dch
            WHERE dch.customer_id = dc.customer_id
              AND dch.payment_date >= date(dc.payment_date, '-30 days')
              AND dch.payment_date < dc.payment_date
        ) AS avg_prev_30_days_sum
    FROM daily_customer AS dc
),
suspicious_days AS (
    SELECT
        dwh.*,
        CASE
            WHEN daily_payment_sum > 0 THEN 1.0 * r_or_nc17_payment_sum / daily_payment_sum
            ELSE NULL
        END AS r_nc17_share
    FROM daily_with_history AS dwh
    WHERE avg_prev_30_days_sum IS NOT NULL
      AND avg_prev_30_days_sum > 0
      AND daily_payment_sum >= 3 * avg_prev_30_days_sum
      AND (staff_count >= 2 OR store_count >= 2)
),
ranked_suspicious AS (
    SELECT
        sd.*,
        RANK() OVER (
            PARTITION BY sd.country, sd.customer_id
            ORDER BY sd.daily_payment_sum DESC
        ) AS country_customer_day_rank
    FROM suspicious_days AS sd
)
SELECT
    customer_id,
    customer_first_name,
    customer_last_name,
    city,
    country,
    payment_date,
    payment_count,
    ROUND(daily_payment_sum, 2) AS daily_payment_sum,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(r_nc17_share, 4) AS r_nc17_share,
    country_customer_day_rank
FROM ranked_suspicious
ORDER BY
    country,
    customer_id,
    country_customer_day_rank,
    payment_date;