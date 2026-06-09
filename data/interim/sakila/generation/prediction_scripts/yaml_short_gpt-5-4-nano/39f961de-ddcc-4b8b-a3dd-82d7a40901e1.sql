WITH payment_enriched AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p03 AS staff_id,
        st.o07 AS staff_store_id,
        cty.d01 AS customer_city_id,
        cty.d02 AS customer_city,
        cnt.c01 AS customer_country_id,
        cnt.c02 AS customer_country,
        CASE
            WHEN f.i11 IN ('R','NC-17') THEN 1
            ELSE 0
        END AS is_r_or_nc17_rental
    FROM pay AS p
    JOIN cus AS cu
        ON cu.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = cu.h06
    JOIN cty
        ON cty.d01 = a.e05
    JOIN cnt
        ON cnt.c01 = cty.d03
    JOIN stf AS st
        ON st.o01 = p.p03
    JOIN ren AS r
        ON r.q01 = p.p04
    JOIN inv AS iinv
        ON iinv.n01 = r.q03
    JOIN flm AS f
        ON f.i01 = iinv.n02
),
daily_customer AS (
    SELECT
        customer_id,
        payment_date,
        customer_city,
        customer_country_id,
        customer_country,
        COUNT(*) AS day_payment_count,
        SUM(payment_amount) AS day_payment_sum,
        MAX(payment_amount) AS max_payment,
        COUNT(DISTINCT staff_id) AS distinct_staff_count,
        COUNT(DISTINCT staff_store_id) AS distinct_store_count,
        SUM(CASE WHEN is_r_or_nc17_rental = 1 THEN payment_amount ELSE 0 END) AS r_or_nc17_payment_sum
    FROM payment_enriched
    GROUP BY
        customer_id,
        payment_date,
        customer_city,
        customer_country_id,
        customer_country
),
daily_with_avg AS (
    SELECT
        dc.*,
        (
            SELECT AVG(d2.day_payment_sum)
            FROM daily_customer AS d2
            WHERE d2.customer_id = dc.customer_id
              AND d2.payment_date >= date(dc.payment_date, '-30 days')
              AND d2.payment_date < dc.payment_date
        ) AS avg_prev_30d_day_sum
    FROM daily_customer AS dc
),
candidates AS (
    SELECT
        d.*,
        (d.day_payment_sum / NULLIF(d.avg_prev_30d_day_sum, 0)) AS ratio_to_prev_avg,
        (d.r_or_nc17_payment_sum / NULLIF(d.day_payment_sum, 0)) AS r_or_nc17_share,
        RANK() OVER (
            PARTITION BY d.customer_country_id
            ORDER BY d.day_payment_sum DESC
        ) AS daily_rank_in_country
    FROM daily_with_avg AS d
    WHERE d.avg_prev_30d_day_sum IS NOT NULL
      AND d.avg_prev_30d_day_sum > 0
      AND d.day_payment_sum >= 3 * d.avg_prev_30d_day_sum
      AND (d.distinct_staff_count >= 3 OR d.distinct_store_count >= 3)
)
SELECT
    customer_city,
    customer_country,
    payment_date,
    day_payment_count AS payment_count,
    ROUND(day_payment_sum, 2) AS day_payment_sum,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(r_or_nc17_share, 4) AS r_or_nc17_rental_share,
    daily_rank_in_country AS day_rank_by_country
FROM candidates
ORDER BY
    customer_country,
    daily_rank_in_country,
    payment_date,
    customer_city;