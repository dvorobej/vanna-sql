WITH daily_payments AS (
    SELECT
        c.h01 AS customer_id,
        cnt_c.c02 AS customer_country,
        date(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS day_amount,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT s_store.j01) AS distinct_store_count
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ct
        ON ct.d01 = a.e05
    JOIN cnt AS cnt_c
        ON cnt_c.c01 = ct.d03
    JOIN stf AS stf_pay
        ON stf_pay.o01 = p.p03
    JOIN sto AS s_store
        ON s_store.j01 = stf_pay.o07
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 <  '2006-01-01'
    GROUP BY
        c.h01,
        cnt_c.c02,
        date(p.p06)
),
daily_history AS (
    SELECT
        dp.customer_id,
        dp.customer_country,
        dp.payment_date,
        dp.payment_count,
        dp.day_amount,
        dp.distinct_staff_count,
        dp.distinct_store_count,
        COALESCE((
            SELECT AVG(dp2.day_amount)
            FROM daily_payments AS dp2
            WHERE dp2.customer_id = dp.customer_id
              AND dp2.payment_date >= DATE(dp.payment_date, '-30 day')
              AND dp2.payment_date <  dp.payment_date
        ), 0) AS avg_day_amount_prev_30d
    FROM daily_payments AS dp
),
diff_country_orders AS (
    SELECT DISTINCT
        c.h01 AS customer_id,
        date(p.p06) AS payment_date,
        cnt_store.c02 AS store_country
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ct
        ON ct.d01 = a.e05
    JOIN cnt AS cnt_customer
        ON cnt_customer.c01 = ct.d03
    JOIN stf AS stf_pay
        ON stf_pay.o01 = p.p03
    JOIN sto AS sto_pay
        ON sto_pay.j01 = stf_pay.o07
    JOIN adr AS a_store
        ON a_store.e01 = sto_pay.j03
    JOIN cty AS ct_store
        ON ct_store.d01 = a_store.e05
    JOIN cnt AS cnt_store
        ON cnt_store.c01 = ct_store.d03
    WHERE date(p.p06) >= '2005-01-01'
      AND date(p.p06) <  '2006-01-01'
      AND cnt_store.c02 <> cnt_customer.c02
),
diff_country_flags AS (
    SELECT
        customer_id,
        payment_date,
        group_concat(DISTINCT store_country, ', ') AS store_countries_other
    FROM diff_country_orders
    GROUP BY customer_id, payment_date
),
daily_country_agg AS (
    SELECT
        dh.customer_id,
        dh.customer_country,
        dh.payment_date,
        dh.payment_count,
        dh.day_amount,
        dh.avg_day_amount_prev_30d,
        dh.distinct_staff_count,
        dh.distinct_store_count,
        dcf.store_countries_other
    FROM daily_history AS dh
    LEFT JOIN diff_country_flags AS dcf
        ON dcf.customer_id = dh.customer_id
       AND dcf.payment_date = dh.payment_date
    WHERE dh.avg_day_amount_prev_30d > 0
      AND dh.payment_count >= 3
      AND dh.day_amount >= 2.0 * dh.avg_day_amount_prev_30d
)
SELECT
    dca.customer_id,
    dca.customer_country,
    dca.payment_date,
    dca.payment_count,
    dca.day_amount,
    dca.avg_day_amount_prev_30d,
    dca.distinct_staff_count,
    dca.distinct_store_count,
    dca.store_countries_other,
    RANK() OVER (
        PARTITION BY dca.customer_country
        ORDER BY (dca.day_amount / dca.avg_day_amount_prev_30d) DESC,
                 dca.day_amount DESC
    ) AS suspicion_rank_in_customer_country
FROM daily_country_agg AS dca
WHERE dca.store_countries_other IS NOT NULL
  AND dca.store_countries_other <> ''
ORDER BY
    dca.customer_country,
    suspicion_rank_in_customer_country,
    dca.payment_date,
    dca.customer_id;