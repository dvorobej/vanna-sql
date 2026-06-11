WITH payments_2005 AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p06 AS payment_date,
        date(p.p06, 'start of month') AS payment_month
    FROM pay AS p
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 < '2006-01-01'
),
customer_base AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        co.c02 AS country_name,
        ci.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ci
        ON ci.d01 = a.e05
    JOIN cnt AS co
        ON co.c01 = ci.d03
),
monthly_customer AS (
    SELECT
        p.customer_id,
        p.payment_month,
        SUM(p.payment_amount) AS month_amount,
        COUNT(*) AS month_payment_count
    FROM payments_2005 AS p
    GROUP BY
        p.customer_id,
        p.payment_month
),
customer_avg AS (
    SELECT
        customer_id,
        AVG(month_amount) AS avg_month_amount_2005
    FROM monthly_customer
    GROUP BY customer_id
),
monthly_customer_scored AS (
    SELECT
        mc.customer_id,
        mc.payment_month,
        mc.month_amount,
        mc.month_payment_count,
        ca.avg_month_amount_2005,
        (mc.month_amount - ca.avg_month_amount_2005) AS deviation_from_personal_avg,
        (mc.month_amount * 1.0 / NULLIF(ca.avg_month_amount_2005, 0)) AS personal_avg_multiplier
    FROM monthly_customer AS mc
    JOIN customer_avg AS ca
        ON ca.customer_id = mc.customer_id
),
country_month_rank AS (
    SELECT
        mcs.*,
        RANK() OVER (
            PARTITION BY cb.country_name, mcs.payment_month
            ORDER BY mcs.month_amount DESC
        ) AS country_month_amount_rank,
        COUNT(*) OVER (
            PARTITION BY cb.country_name, mcs.payment_month
        ) AS country_month_customer_count
    FROM monthly_customer_scored AS mcs
    JOIN customer_base AS cb
        ON cb.customer_id = mcs.customer_id
),
country_month_top10 AS (
    SELECT
        cmr.*,
        CAST(cmr.country_month_customer_count * 0.10 AS INTEGER) AS top10_threshold
    FROM country_month_rank AS cmr
),
country_month_filtered AS (
    SELECT
        cmr.customer_id,
        cmr.payment_month,
        cmr.month_amount,
        cmr.month_payment_count,
        cmr.avg_month_amount_2005,
        cmr.deviation_from_personal_avg,
        cmr.country_month_rank,
        cmr.country_month_customer_count
    FROM country_month_top10 AS cmr
    WHERE cmr.avg_month_amount_2005 IS NOT NULL
      AND cmr.avg_month_amount_2005 > 0
      AND cmr.personal_avg_multiplier > 2.0
      AND cmr.country_month_amount_rank <= cmr.top10_threshold
),
top_staff_by_amount AS (
    SELECT
        p.customer_id,
        date(p.payment_date, 'start of month') AS payment_month,
        p.staff_id,
        SUM(CAST(p.payment_amount AS REAL)) AS staff_month_amount,
        ROW_NUMBER() OVER (
            PARTITION BY p.customer_id, date(p.payment_date, 'start of month')
            ORDER BY SUM(CAST(p.payment_amount AS REAL)) DESC, p.staff_id
        ) AS rn
    FROM payments_2005 AS p
    GROUP BY
        p.customer_id,
        date(p.payment_date, 'start of month'),
        p.staff_id
)
SELECT
    c.customer_id,
    c.country_name AS country,
    c.city_name AS city,
    strftime('%Y-%m', cmf.payment_month) AS month,
    ROUND(cmf.month_amount, 2) AS month_amount,
    cmf.month_payment_count AS payment_count,
    ROUND(cmf.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
    cmf.country_month_amount_rank AS country_rank_in_month,
    st.o01 AS top_staff_id,
    st.o02 || ' ' || st.o03 AS top_staff_name,
    ts.staff_month_amount AS top_staff_amount
FROM country_month_filtered AS cmf
JOIN customer_base AS c
    ON c.customer_id = cmf.customer_id
JOIN top_staff_by_amount AS ts
    ON ts.customer_id = cmf.customer_id
   AND ts.payment_month = cmf.payment_month
   AND ts.rn = 1
JOIN stf AS st
    ON st.o01 = ts.staff_id
ORDER BY
    c.country_name,
    cmf.payment_month,
    cmf.month_amount DESC,
    c.customer_id;