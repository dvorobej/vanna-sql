WITH payment_base AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p03 AS staff_id,
        st.o07 AS staff_store_id,
        c.h06 AS customer_address_id,
        cust_addr.e01 AS customer_address_pk,
        ci.d02 AS customer_city,
        co.c02 AS customer_country,
        r.q01 AS rental_id,
        inv.n02 AS film_id,
        f.i11 AS film_rating
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS cust_addr
        ON cust_addr.e01 = c.h06
    JOIN cty AS ci
        ON ci.d01 = cust_addr.e05
    JOIN cnt AS co
        ON co.c01 = ci.d03
    JOIN stf AS st
        ON st.o01 = p.p03
    LEFT JOIN ren AS r
        ON r.q01 = p.p04
    LEFT JOIN inv
        ON inv.n01 = r.q03
    LEFT JOIN flm AS f
        ON f.i01 = inv.n02
    WHERE p.p05 IS NOT NULL
),
daily_summaries AS (
    SELECT
        customer_id,
        payment_date,
        MAX(customer_city) AS customer_city,
        MAX(customer_country) AS customer_country,
        COUNT(*) AS payment_count,
        SUM(payment_amount) AS daily_total_amount,
        MAX(payment_amount) AS max_single_payment,
        COUNT(DISTINCT staff_id) AS staff_count,
        COUNT(DISTINCT staff_store_id) AS store_count,
        SUM(CASE WHEN film_rating IN ('R', 'NC-17') THEN payment_amount ELSE 0 END) AS r_or_nc17_amount
    FROM payment_base
    GROUP BY
        customer_id,
        payment_date
),
with_history AS (
    SELECT
        ds.*,
        (
            SELECT AVG(ds2.daily_total_amount)
            FROM daily_summaries AS ds2
            WHERE ds2.customer_id = ds.customer_id
              AND ds2.payment_date >= date(ds.payment_date, '-30 days')
              AND ds2.payment_date < ds.payment_date
        ) AS avg_prev_30_days_amount
    FROM daily_summaries AS ds
),
suspicious_days AS (
    SELECT
        wh.*,
        CASE
            WHEN wh.daily_total_amount > 0 THEN 1.0 * wh.r_or_nc17_amount / wh.daily_total_amount
            ELSE 0
        END AS r_or_nc17_share
    FROM with_history AS wh
    WHERE wh.avg_prev_30_days_amount IS NOT NULL
      AND wh.avg_prev_30_days_amount > 0
      AND wh.daily_total_amount >= 2.0 * wh.avg_prev_30_days_amount
      AND (wh.staff_count > 1 OR wh.store_count > 1)
)
SELECT
    c.h03 AS customer_first_name,
    c.h04 AS customer_last_name,
    sd.customer_address_id AS customer_address_id,
    sd.customer_city,
    sd.customer_country,
    sd.payment_date,
    sd.payment_count,
    ROUND(sd.daily_total_amount, 2) AS daily_total_amount,
    ROUND(sd.max_single_payment, 2) AS max_single_payment,
    ROUND(sd.r_or_nc17_share, 4) AS r_or_nc17_share,
    RANK() OVER (
        PARTITION BY sd.customer_country
        ORDER BY sd.daily_total_amount DESC
    ) AS suspicion_rank_within_country
FROM suspicious_days AS sd
JOIN cus AS c
    ON c.h01 = sd.customer_id
ORDER BY
    sd.customer_country,
    suspicion_rank_within_country,
    sd.customer_id,
    sd.payment_date;