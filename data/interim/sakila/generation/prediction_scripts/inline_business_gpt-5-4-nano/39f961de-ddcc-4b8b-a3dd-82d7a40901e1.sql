WITH payment_enriched AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        c.h03 AS customer_first_name,
        c.h04 AS customer_last_name,
        a.e01 AS customer_address_id,
        c.h06 AS customer_address_ref,
        cu_city.d02 AS customer_city,
        cu_country.c02 AS customer_country,
        date(p.p06) AS payment_date,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p03 AS staff_id,
        st.o07 AS store_id,
        fl.i11 AS film_rating
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS cu_city
        ON cu_city.d01 = a.e05
    JOIN cnt AS cu_country
        ON cu_country.c01 = cu_city.d03
    JOIN stf AS stf
        ON stf.o01 = p.p03
    JOIN sto AS st
        ON st.j01 = stf.o07
    LEFT JOIN ren AS r
        ON r.q01 = p.p04
    LEFT JOIN inv AS iinv
        ON iinv.n01 = r.q03
    LEFT JOIN flm AS fl
        ON fl.i01 = iinv.n02
    WHERE p.p06 IS NOT NULL
      AND p.p04 IS NOT NULL
),
daily_activity AS (
    SELECT
        pe.customer_id,
        pe.customer_first_name,
        pe.customer_last_name,
        pe.customer_city,
        pe.customer_country,
        pe.payment_date,
        COUNT(pe.payment_id) AS payment_count,
        SUM(pe.payment_amount) AS daily_payment_sum,
        MAX(pe.payment_amount) AS max_payment,
        COUNT(DISTINCT pe.staff_id) AS staff_count,
        COUNT(DISTINCT pe.store_id) AS store_count,
        SUM(CASE WHEN pe.film_rating IN ('R','NC-17') THEN pe.payment_amount ELSE 0 END) AS r_nc17_payment_sum
    FROM payment_enriched AS pe
    GROUP BY
        pe.customer_id,
        pe.customer_first_name,
        pe.customer_last_name,
        pe.customer_city,
        pe.customer_country,
        pe.payment_date
),
with_history AS (
    SELECT
        da.*,
        (
            SELECT AVG(da2.daily_payment_sum)
            FROM daily_activity da2
            WHERE da2.customer_id = da.customer_id
              AND da2.payment_date >= date(da.payment_date, '-30 days')
              AND da2.payment_date < da.payment_date
        ) AS avg_prev_30d_daily_sum
    FROM daily_activity AS da
),
suspicious_days AS (
    SELECT
        wh.*,
        (wh.r_nc17_payment_sum * 1.0 / NULLIF(wh.daily_payment_sum, 0)) AS r_nc17_share,
        (wh.daily_payment_sum / NULLIF(wh.avg_prev_30d_daily_sum, 0)) AS ratio_prev_avg
    FROM with_history AS wh
    WHERE wh.avg_prev_30d_daily_sum IS NOT NULL
      AND wh.staff_count >= 2
      AND wh.store_count >= 2
      AND wh.daily_payment_sum >= 2.0 * wh.avg_prev_30d_daily_sum
)
SELECT
    sd.customer_id,
    sd.customer_first_name,
    sd.customer_last_name,
    sd.customer_address_id,
    sd.customer_city,
    sd.customer_country,
    sd.payment_date,
    sd.payment_count,
    ROUND(sd.daily_payment_sum, 2) AS daily_payment_sum,
    ROUND(sd.max_payment, 2) AS max_payment,
    ROUND(sd.r_nc17_share, 4) AS r_nc17_payment_share,
    RANK() OVER (
        PARTITION BY sd.customer_country
        ORDER BY sd.daily_payment_sum DESC
    ) AS suspicion_rank_in_country,
    ROUND(sd.ratio_prev_avg, 2) AS ratio_to_prev_avg
FROM suspicious_days AS sd
ORDER BY
    sd.customer_country,
    suspicion_rank_in_country,
    sd.customer_id,
    sd.payment_date;