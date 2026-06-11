WITH payment_enriched AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        p.p04 AS rental_id,
        CAST(p.p05 AS REAL) AS payment_amount,
        date(p.p06) AS payment_date,
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        sto.j01 AS store_id
    FROM pay AS p
    JOIN cus AS cu
      ON cu.h01 = p.p02
    JOIN adr AS ca
      ON ca.e01 = cu.h06
    JOIN cty
      ON cty.d01 = ca.e05
    JOIN cnt
      ON cnt.c01 = cty.d03
    JOIN stf AS st
      ON st.o01 = p.p03
    LEFT JOIN sto
      ON sto.j01 = st.o07
),
daily_customer AS (
    SELECT
        customer_id,
        country_name,
        city_name,
        payment_date,
        COUNT(*) AS payment_count,
        SUM(payment_amount) AS day_amount,
        COUNT(DISTINCT staff_id) AS distinct_staff_count,
        COUNT(DISTINCT store_id) AS distinct_store_count
    FROM payment_enriched
    GROUP BY
        customer_id,
        country_name,
        city_name,
        payment_date
),
with_personal_avg AS (
    SELECT
        dc.*,
        (
            SELECT AVG(dcp.day_amount)
            FROM daily_customer AS dcp
            WHERE dcp.customer_id = dc.customer_id
              AND dcp.payment_date >= date(dc.payment_date, '-30 days')
              AND dcp.payment_date < dc.payment_date
        ) AS avg_daily_prev_30
    FROM daily_customer AS dc
),
suspicious_days AS (
    SELECT
        wpa.*,
        (day_amount / NULLIF(avg_daily_prev_30, 0)) AS exceed_ratio
    FROM with_personal_avg AS wpa
    WHERE avg_daily_prev_30 IS NOT NULL
      AND avg_daily_prev_30 > 0
      AND day_amount >= 3.0 * avg_daily_prev_30
      AND payment_count >= 3
      AND (distinct_staff_count >= 2 OR distinct_store_count >= 2)
),
ranked_days AS (
    SELECT
        sd.*,
        RANK() OVER (
            PARTITION BY sd.customer_id
            ORDER BY sd.day_amount DESC
        ) AS day_amount_rank_within_customer
    FROM suspicious_days AS sd
)
SELECT
    customer_id,
    country_name,
    city_name,
    payment_date AS suspicious_date,
    payment_count,
    ROUND(day_amount, 2) AS total_amount,
    ROUND(avg_daily_prev_30, 2) AS avg_daily_prev_30_days_amount,
    ROUND(exceed_ratio, 4) AS exceed_ratio,
    day_amount_rank_within_customer AS day_rank_for_customer
FROM ranked_days
ORDER BY
    customer_id,
    day_rank_for_customer,
    suspicious_date;