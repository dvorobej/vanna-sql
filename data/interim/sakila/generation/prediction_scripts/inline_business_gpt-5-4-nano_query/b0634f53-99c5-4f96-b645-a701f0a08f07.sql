WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        co.c02 AS customer_country,
        ci.d02 AS customer_city
    FROM cus c
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ci ON ci.d01 = a.e05
    JOIN cnt co ON co.c01 = ci.d03
),
daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_sum,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT st.o07) AS store_count,
        GROUP_CONCAT(DISTINCT sm_country.c02) AS store_countries_list,
        COUNT(DISTINCT CASE WHEN sm_country.c02 <> cg.customer_country THEN sm_country.c02 END) AS distinct_non_home_store_countries,
        MAX(CASE WHEN sm_country.c02 <> cg.customer_country THEN 1 ELSE 0 END) AS has_non_home_country_payment
    FROM pay p
    JOIN customer_geo cg
        ON cg.customer_id = p.p02
    JOIN stf st
        ON st.o01 = p.p03
    JOIN sto s
        ON s.j01 = st.o07
    JOIN adr sa
        ON sa.e01 = s.j03
    JOIN cty ci
        ON ci.d01 = sa.e05
    JOIN cnt sm_country
        ON sm_country.c01 = ci.d03
    WHERE date(p.p06) >= '2005-01-01'
      AND date(p.p06) <  '2006-01-01'
    GROUP BY
        p.p02,
        date(p.p06)
),
with_history AS (
    SELECT
        dp.*,
        (
            SELECT AVG(dp2.day_sum)
            FROM daily_payments dp2
            WHERE dp2.customer_id = dp.customer_id
              AND dp2.payment_date >= date(dp.payment_date, '-30 day')
              AND dp2.payment_date <  dp.payment_date
        ) AS avg_day_sum_prev_30d
    FROM daily_payments dp
),
suspicious_days AS (
    SELECT
        wh.*,
        (wh.day_sum / NULLIF(wh.avg_day_sum_prev_30d, 0.0)) AS exceed_ratio
    FROM with_history wh
    WHERE wh.avg_day_sum_prev_30d IS NOT NULL
      AND wh.avg_day_sum_prev_30d > 0
      AND wh.payment_count >= 3
      AND wh.day_sum >= 2.0 * wh.avg_day_sum_prev_30d
      AND wh.has_non_home_country_payment = 1
),
ranked AS (
    SELECT
        sd.*,
        RANK() OVER (
            PARTITION BY sd.customer_id_country
            ORDER BY sd.exceed_ratio DESC, sd.day_sum DESC, sd.payment_date
        ) AS customer_country_risk_rank
    FROM (
        SELECT
            sd.*,
            cg.customer_country AS customer_id_country
        FROM suspicious_days sd
        JOIN customer_geo cg ON cg.customer_id = sd.customer_id
    ) sd
)
SELECT
    r.customer_id,
    cg.customer_city,
    cg.customer_country,
    r.payment_date,
    r.payment_count,
    ROUND(r.day_sum, 2) AS day_sum,
    ROUND(r.avg_day_sum_prev_30d, 2) AS avg_day_sum_prev_30d,
    r.staff_count,
    r.store_count,
    r.store_countries_list,
    r.exceed_ratio,
    r.customer_country_risk_rank
FROM ranked r
JOIN customer_geo cg
    ON cg.customer_id = r.customer_id
ORDER BY
    cg.customer_country,
    r.customer_country_risk_rank,
    r.payment_date,
    r.customer_id;