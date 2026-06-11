WITH payment_enriched AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        p.p04 AS rental_id,
        CAST(p.p05 AS REAL) AS payment_amount,
        DATE(p.p06) AS payment_day,
        cu.h02 AS customer_home_store_id,
        cnt_home.c01 AS customer_country_id,
        cnt_home.c02 AS customer_country_name,
        st.o07 AS staff_store_id,
        cnt_staff.c02 AS staff_store_country_name
    FROM pay AS p
    JOIN cus AS cu
        ON cu.h01 = p.p02
    JOIN adr AS a_home
        ON a_home.e01 = cu.h06
    JOIN cty AS ci_home
        ON ci_home.d01 = a_home.e05
    JOIN cnt AS cnt_home
        ON cnt_home.c01 = ci_home.d03
    JOIN stf AS st
        ON st.o01 = p.p03
    JOIN sto AS sto_staff
        ON sto_staff.j01 = st.o07
    JOIN adr AS a_staff
        ON a_staff.e01 = sto_staff.j03
    JOIN cty AS ci_staff
        ON ci_staff.d01 = a_staff.e05
    JOIN cnt AS cnt_staff
        ON cnt_staff.c01 = ci_staff.d03
),
daily_customer AS (
    SELECT
        customer_id,
        payment_day,
        customer_country_id,
        customer_country_name,
        COUNT(*) AS payment_count,
        SUM(payment_amount) AS day_payment_sum,
        COUNT(DISTINCT staff_id) AS staff_count,
        COUNT(DISTINCT staff_store_id) AS store_count,
        COUNT(DISTINCT CASE WHEN staff_store_country_name <> customer_country_name THEN staff_store_id END) AS foreign_store_count
    FROM payment_enriched
    GROUP BY
        customer_id,
        payment_day,
        customer_country_id,
        customer_country_name
),
daily_with_prev AS (
    SELECT
        dc.*,
        (
            SELECT AVG(dc2.day_payment_sum)
            FROM daily_customer AS dc2
            WHERE dc2.customer_id = dc.customer_id
              AND dc2.payment_day >= date(dc.payment_day, '-30 day')
              AND dc2.payment_day <  dc.payment_day
        ) AS avg_daily_sum_prev_30d
    FROM daily_customer AS dc
),
suspicious_days AS (
    SELECT
        dwp.*,
        (dwp.day_payment_sum / dwp.avg_daily_sum_prev_30d) AS spike_ratio
    FROM daily_with_prev AS dwp
    WHERE dwp.payment_count >= 3
      AND dwp.avg_daily_sum_prev_30d IS NOT NULL
      AND dwp.avg_daily_sum_prev_30d > 0
      AND dwp.day_payment_sum >= 2.0 * dwp.avg_daily_sum_prev_30d
      AND dwp.store_count > 1
      AND dwp.foreign_store_count >= 1
)
SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    sd.payment_day,
    sd.customer_country_name AS customer_country,
    sd.payment_count,
    ROUND(sd.day_payment_sum, 2) AS day_payment_sum,
    ROUND(sd.avg_daily_sum_prev_30d, 2) AS avg_daily_sum_prev_30d,
    sd.staff_count AS distinct_staff_count,
    sd.store_count AS distinct_store_count,
    GROUP_CONCAT(DISTINCT pe.staff_store_country_name) AS store_countries,
    RANK() OVER (
        PARTITION BY sd.customer_country_id
        ORDER BY (sd.day_payment_sum / sd.avg_daily_sum_prev_30d) DESC, sd.day_payment_sum DESC, sd.payment_day
    ) AS suspicious_rank_within_country
FROM suspicious_days AS sd
JOIN cus AS c
    ON c.h01 = sd.customer_id
JOIN payment_enriched AS pe
    ON pe.customer_id = sd.customer_id
   AND pe.payment_day = sd.payment_day
WHERE sd.payment_day >= '2005-01-01'
  AND sd.payment_day <  '2006-01-01'
GROUP BY
    c.h01,
    c.h03,
    c.h04,
    sd.payment_day,
    sd.customer_country_name,
    sd.payment_count,
    sd.day_payment_sum,
    sd.avg_daily_sum_prev_30d,
    sd.staff_count,
    sd.store_count,
    sd.customer_country_id
ORDER BY
    sd.customer_country_name,
    suspicious_rank_within_country,
    sd.payment_day;