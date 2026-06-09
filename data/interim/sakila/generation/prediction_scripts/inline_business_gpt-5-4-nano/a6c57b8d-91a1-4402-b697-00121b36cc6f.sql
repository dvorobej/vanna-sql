WITH payment_enriched AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        p.p03 AS staff_id,
        st.o07 AS store_id,
        date(p.p06, 'start of month') AS month_start,
        COUNT(*) OVER (PARTITION BY p.p02, date(p.p06, 'start of month')) AS dummy_cnt,
        CAST(p.p05 AS REAL) AS payment_amount,
        cu_city.d02 AS city,
        cu_cnt.c01 AS country_id,
        cu_cnt.c02 AS country
    FROM pay p
    JOIN cus c
        ON c.h01 = p.p02
    JOIN adr cu_adr
        ON cu_adr.e01 = c.h06
    JOIN cty cu_city_id
        ON cu_city_id.d01 = cu_adr.e05
    JOIN cty cu_city
        ON cu_city.d01 = cu_city_id.d01
    JOIN cnt cu_cnt
        ON cu_cnt.c01 = cu_city.d03
    JOIN stf st
        ON st.o01 = p.p03
    JOIN sto stt
        ON stt.j01 = st.o07
),
monthly_customer AS (
    SELECT
        pe.customer_id,
        MAX(pe.customer_name) AS customer_name,
        MAX(pe.country_id) AS country_id,
        MAX(pe.country) AS country,
        MAX(pe.city) AS city,
        pe.month_start,
        COUNT(*) AS payment_count,
        SUM(pe.payment_amount) AS month_total_amount
    FROM payment_enriched pe
    GROUP BY
        pe.customer_id,
        pe.month_start
),
monthly_with_personal_avg AS (
    SELECT
        mc.*,
        AVG(mc.month_total_amount) OVER (
            PARTITION BY mc.customer_id
            ORDER BY mc.month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS personal_avg_month_total_amount
    FROM monthly_customer mc
),
country_month_ranked AS (
    SELECT
        mpa.*,
        RANK() OVER (
            PARTITION BY mpa.country_id, mpa.month_start
            ORDER BY mpa.month_total_amount DESC
        ) AS amount_rank_desc,
        COUNT(*) OVER (
            PARTITION BY mpa.country_id, mpa.month_start
        ) AS country_customers_count
    FROM monthly_with_personal_avg mpa
),
top_staff_per_month AS (
    SELECT
        pe.customer_id,
        pe.month_start,
        pe.country_id,
        pe.staff_id,
        SUM(pe.payment_amount) AS staff_month_total_amount,
        ROW_NUMBER() OVER (
            PARTITION BY pe.customer_id, pe.month_start
            ORDER BY SUM(pe.payment_amount) DESC, pe.staff_id
        ) AS rn
    FROM payment_enriched pe
    GROUP BY
        pe.customer_id,
        pe.month_start,
        pe.country_id,
        pe.staff_id
),
monthly_top_staff AS (
    SELECT
        customer_id,
        month_start,
        country_id,
        staff_id,
        staff_month_total_amount
    FROM top_staff_per_month
    WHERE rn = 1
)
SELECT
    cm.country,
    cm.city,
    cm.customer_id,
    cm.customer_name,
    strftime('%Y-%m', cm.month_start) AS activity_month,
    ROUND(cm.month_total_amount, 2) AS month_total_amount,
    cm.payment_count,
    ROUND(cm.month_total_amount - cm.personal_avg_month_total_amount, 2) AS deviation_from_personal_avg,
    ROUND(cm.personal_avg_month_total_amount, 2) AS personal_avg_month_total_amount,
    cm.amount_rank_desc AS country_month_amount_rank_desc,
    ROUND(
        1.0 * cm.amount_rank_desc / NULLIF(cm.country_customers_count, 0),
        4
    ) AS country_amount_percent_rank_like,
    ts.staff_id AS top_staff_id,
    st.o02 AS top_staff_first_name,
    st.o03 AS top_staff_last_name,
    ROUND(ts.staff_month_total_amount, 2) AS top_staff_month_total_amount
FROM country_month_ranked cm
JOIN monthly_top_staff ts
    ON ts.customer_id = cm.customer_id
   AND ts.month_start = cm.month_start
   AND ts.country_id = cm.country_id
JOIN stf st
    ON st.o01 = ts.staff_id
WHERE
    cm.month_total_amount > 0
    AND cm.personal_avg_month_total_amount IS NOT NULL
    AND cm.personal_avg_month_total_amount > 0
    AND cm.month_total_amount >= 3.0 * cm.personal_avg_month_total_amount
    AND (1.0 * cm.amount_rank_desc / NULLIF(cm.country_customers_count, 0)) <= 0.10
ORDER BY
    cm.country,
    cm.month_start,
    cm.month_total_amount DESC,
    cm.customer_id;