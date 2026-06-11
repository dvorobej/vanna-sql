WITH payment_enriched AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p03 AS staff_id,
        sf.o07 AS staff_store_id,
        c.h02 AS customer_home_store_id,
        cn.c01 AS country_id
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ci
        ON ci.d01 = a.e05
    JOIN cnt AS cn
        ON cn.c01 = ci.d03
    JOIN stf AS sf
        ON sf.o01 = p.p03
),
monthly_customer AS (
    SELECT
        pe.customer_id,
        pe.month_start,
        pe.country_id,
        COUNT(pe.payment_id) AS payment_count,
        SUM(pe.payment_amount) AS monthly_amount,
        AVG(pe.payment_amount) AS avg_check,
        SUM(CASE WHEN strftime('%d', pe.month_start, '+0 day') IS NOT NULL THEN 0 ELSE 0 END) AS dummy,
        GROUP_CONCAT(
            DISTINCT strftime('%Y-%m-%d', pe.month_start)
        ) AS dummy2
    FROM payment_enriched AS pe
    GROUP BY
        pe.customer_id,
        pe.month_start,
        pe.country_id
),
monthly_customer_days AS (
    SELECT
        pe.customer_id,
        pe.month_start,
        GROUP_CONCAT(
            strftime('%Y-%m-%d', pe.month_start) || ':' || CAST(cnt_day.day_amount AS TEXT)
        ) AS payments_by_day
    FROM (
        SELECT
            p.p02 AS customer_id,
            date(p.p06, 'start of month') AS month_start,
            date(p.p06) AS day_start,
            SUM(CAST(p.p05 AS REAL)) AS day_amount
        FROM pay p
        GROUP BY p.p02, date(p.p06, 'start of month'), date(p.p06)
    ) AS cnt_day
    JOIN payment_enriched pe
      ON pe.customer_id = cnt_day.customer_id
     AND pe.month_start = cnt_day.month_start
    GROUP BY pe.customer_id, pe.month_start
),
monthly_with_history AS (
    SELECT
        mc.*,
        LAG(mc.monthly_amount) OVER (
            PARTITION BY mc.customer_id
            ORDER BY mc.month_start
        ) AS prev_month_amount
    FROM monthly_customer mc
),
country_month_avg AS (
    SELECT
        mwh.country_id,
        mwh.month_start,
        AVG(mwh.monthly_amount) AS country_avg_monthly_amount
    FROM monthly_with_history mwh
    GROUP BY mwh.country_id, mwh.month_start
),
candidate_months AS (
    SELECT
        mwh.*,
        cma.country_avg_monthly_amount,
        (mwh.monthly_amount - mwh.prev_month_amount) AS delta_from_prev,
        CASE
            WHEN mwh.prev_month_amount IS NULL OR mwh.prev_month_amount = 0 THEN NULL
            ELSE mwh.monthly_amount / mwh.prev_month_amount
        END AS ratio_to_prev_month,
        CASE
            WHEN cma.country_avg_monthly_amount IS NULL OR cma.country_avg_monthly_amount = 0 THEN NULL
            ELSE mwh.monthly_amount / cma.country_avg_monthly_amount
        END AS ratio_to_country_avg
    FROM monthly_with_history mwh
    JOIN country_month_avg cma
      ON cma.country_id = mwh.country_id
     AND cma.month_start = mwh.month_start
    WHERE mwh.prev_month_amount IS NOT NULL
),
monthly_rank AS (
    SELECT
        mwh.country_id,
        mwh.month_start,
        mwh.customer_id,
        RANK() OVER (
            PARTITION BY mwh.country_id, mwh.month_start
            ORDER BY mwh.monthly_amount DESC
        ) AS country_month_amount_rank
    FROM monthly_with_history mwh
),
top_staff_in_month AS (
    SELECT
        pe.customer_id,
        pe.month_start,
        pe.country_id,
        pe.staff_id,
        SUM(pe.payment_amount) AS staff_month_amount,
        ROW_NUMBER() OVER (
            PARTITION BY pe.customer_id, pe.month_start
            ORDER BY SUM(pe.payment_amount) DESC, pe.staff_id
        ) AS rn
    FROM payment_enriched pe
    GROUP BY pe.customer_id, pe.month_start, pe.country_id, pe.staff_id
),
joined AS (
    SELECT
        cm.country_id,
        cm.month_start,
        cm.customer_id,
        c.h02 AS customer_store_id,
        c.h06 AS customer_address_id,
        c.h03,
        c.h04,
        ci.d02 AS customer_city,
        cn.c02 AS customer_country,
        ms.country_month_amount_rank,
        cm.payment_count,
        cm.monthly_amount,
        cm.avg_check,
        cm.ratio_to_prev_month,
        cm.ratio_to_country_avg,
        cm.country_avg_monthly_amount,
        ts.staff_id AS top_staff_id,
        ts_staff.o02 || ' ' || ts_staff.o03 AS top_staff_name
    FROM candidate_months cm
    JOIN cus c
      ON c.h01 = cm.customer_id
    JOIN adr a
      ON a.e01 = c.h06
    JOIN cty ci
      ON ci.d01 = a.e05
    JOIN cnt cn
      ON cn.c01 = ci.d03
    JOIN monthly_rank ms
      ON ms.country_id = cm.country_id
     AND ms.month_start = cm.month_start
     AND ms.customer_id = cm.customer_id
    LEFT JOIN top_staff_in_month ts
      ON ts.customer_id = cm.customer_id
     AND ts.month_start = cm.month_start
     AND ts.country_id = cm.country_id
     AND ts.rn = 1
    LEFT JOIN stf ts_staff
      ON ts_staff.o01 = ts.staff_id
)
SELECT
    j.customer_id,
    j.h03 AS first_name,
    j.h04 AS last_name,
    j.customer_store_id AS store_id,
    j.customer_country,
    j.customer_city,
    j.month_start AS payment_month,
    ROUND(j.monthly_amount, 2) AS monthly_amount,
    j.payment_count,
    ROUND(j.avg_check, 2) AS avg_check,
    ROUND(j.country_avg_monthly_amount, 2) AS country_avg_monthly_amount,
    ROUND(j.ratio_to_prev_month, 4) AS ratio_to_prev_month_amount,
    ROUND(j.ratio_to_country_avg, 4) AS ratio_to_country_avg,
    j.country_month_amount_rank,
    j.top_staff_id,
    j.top_staff_name
FROM joined j
WHERE (j.ratio_to_prev_month >= 2.0)
   OR (j.ratio_to_country_avg >= 1.5)
ORDER BY
    j.customer_country,
    j.payment_month,
    j.country_month_amount_rank,
    j.monthly_amount DESC,
    j.customer_id;