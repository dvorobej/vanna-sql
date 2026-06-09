WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        c.h02 AS registration_store_id,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        ci.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt ON cnt.c01 = ci.d03
),
monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count,
        AVG(p.p05) AS avg_check,
        SUM(CASE WHEN strftime('%d', p.p06) IN ('01','02','03','04','05','06','07','08','09','10','11','12','13','14','15','16','17','18','19','20') THEN 1 ELSE 0 END) AS day_bucket_1_20_count,
        SUM(CASE WHEN strftime('%d', p.p06) IN ('21','22','23','24','25','26','27','28','29','30','31') THEN 1 ELSE 0 END) AS day_bucket_21_31_count,
        SUM(CASE WHEN strftime('%d', p.p06) IN ('01','02','03','04','05','06','07','08','09','10','11','12','13','14','15','16','17','18','19','20') THEN p.p05 ELSE 0 END) AS day_bucket_1_20_amount,
        SUM(CASE WHEN strftime('%d', p.p06) IN ('21','22','23','24','25','26','27','28','29','30','31') THEN p.p05 ELSE 0 END) AS day_bucket_21_31_amount
    FROM pay AS p
    GROUP BY
        p.p02,
        date(p.p06, 'start of month')
),
monthly_with_history AS (
    SELECT
        mp.*,
        cg.first_name,
        cg.last_name,
        cg.registration_store_id,
        cg.country_id,
        cg.country_name,
        cg.city_name,
        LAG(mp.monthly_amount) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.month_start
        ) AS prev_month_amount
    FROM monthly_payments AS mp
    JOIN customer_geo AS cg
      ON cg.customer_id = mp.customer_id
),
country_month_avg AS (
    SELECT
        month_start,
        country_id,
        AVG(monthly_amount) AS country_avg_monthly_amount
    FROM monthly_with_history
    GROUP BY
        month_start,
        country_id
),
with_country_and_staff AS (
    SELECT
        mwh.*,
        cmaa.country_avg_monthly_amount
    FROM monthly_with_history AS mwh
    JOIN country_month_avg AS cmaa
      ON cmaa.month_start = mwh.month_start
     AND cmaa.country_id = mwh.country_id
),
top_staff_in_month AS (
    SELECT
        x.customer_id,
        x.month_start,
        x.staff_id,
        x.staff_payment_amount,
        x.staff_payment_count,
        ROW_NUMBER() OVER (
            PARTITION BY x.customer_id, x.month_start
            ORDER BY x.staff_payment_amount DESC, x.staff_payment_count DESC, x.staff_id
        ) AS rn
    FROM (
        SELECT
            p.p02 AS customer_id,
            date(p.p06, 'start of month') AS month_start,
            p.p03 AS staff_id,
            SUM(p.p05) AS staff_payment_amount,
            COUNT(*) AS staff_payment_count
        FROM pay AS p
        GROUP BY
            p.p02,
            date(p.p06, 'start of month'),
            p.p03
    ) AS x
),
top_staff_details AS (
    SELECT
        tsim.customer_id,
        tsim.month_start,
        tsim.staff_id,
        s.o02 || ' ' || s.o03 AS staff_name,
        tsim.staff_payment_amount,
        tsim.staff_payment_count
    FROM top_staff_in_month AS tsim
    JOIN stf AS s
      ON s.o01 = tsim.staff_id
    WHERE tsim.rn = 1
),
top_store_in_month AS (
    SELECT
        x.customer_id,
        x.month_start,
        x.staff_store_id,
        x.store_payment_amount,
        x.store_payment_count,
        ROW_NUMBER() OVER (
            PARTITION BY x.customer_id, x.month_start
            ORDER BY x.store_payment_amount DESC, x.store_payment_count DESC, x.staff_store_id
        ) AS rn
    FROM (
        SELECT
            p.p02 AS customer_id,
            date(p.p06, 'start of month') AS month_start,
            sf.o07 AS staff_store_id,
            SUM(p.p05) AS store_payment_amount,
            COUNT(*) AS store_payment_count
        FROM pay AS p
        JOIN stf AS sf ON sf.o01 = p.p03
        GROUP BY
            p.p02,
            date(p.p06, 'start of month'),
            sf.o07
    ) AS x
),
top_store_details AS (
    SELECT
        tstd.customer_id,
        tstd.month_start,
        tstd.staff_store_id AS store_id,
        tstd.store_payment_amount,
        tstd.store_payment_count
    FROM top_store_in_month AS tstd
    WHERE tstd.rn = 1
),
country_rank_month AS (
    SELECT
        mwh.country_id,
        mwh.month_start,
        mwh.customer_id,
        RANK() OVER (
            PARTITION BY mwh.country_id, mwh.month_start
            ORDER BY mwh.monthly_amount DESC
        ) AS customer_country_month_rank
    FROM monthly_with_history AS mwh
)
SELECT
    wcc.customer_id,
    wcc.first_name,
    wcc.last_name,
    wcc.country_id,
    wcc.country_name,
    wcc.city_name,
    wcc.month_start AS month,
    ROUND(wcc.monthly_amount, 2) AS monthly_amount,
    wcc.payment_count,
    ROUND(wcc.avg_check, 2) AS avg_check,
    ROUND(CASE WHEN wcc.payment_count > 0 THEN 1.0 * wcc.day_bucket_1_20_count / wcc.payment_count ELSE 0 END, 4) AS day_bucket_1_20_share_count,
    ROUND(CASE WHEN wcc.monthly_amount > 0 THEN 1.0 * wcc.day_bucket_1_20_amount / wcc.monthly_amount ELSE 0 END, 4) AS day_bucket_1_20_share_amount,
    ROUND(CASE WHEN wcc.prev_month_amount IS NULL THEN NULL ELSE wcc.monthly_amount - wcc.prev_month_amount END, 2) AS change_vs_prev_month_amount,
    ROUND(CASE
        WHEN wcc.prev_month_amount IS NULL OR wcc.prev_month_amount = 0 THEN NULL
        ELSE wcc.monthly_amount / wcc.prev_month_amount
    END, 4) AS ratio_to_prev_month,
    ROUND(wcc.country_avg_monthly_amount, 2) AS country_avg_monthly_amount,
    ROUND(CASE
        WHEN wcc.country_avg_monthly_amount IS NULL OR wcc.country_avg_monthly_amount = 0 THEN NULL
        ELSE wcc.monthly_amount / wcc.country_avg_monthly_amount
    END, 4) AS ratio_to_country_avg,
    crmr.customer_country_month_rank AS country_month_amount_rank,
    ts.staff_id AS top_staff_id,
    ts.staff_name AS top_staff_name,
    ts.staff_payment_count AS top_staff_payment_count,
    ROUND(ts.staff_payment_amount, 2) AS top_staff_payment_amount,
    td.store_id AS top_store_id,
    td.store_payment_count AS top_store_payment_count,
    ROUND(td.store_payment_amount, 2) AS top_store_payment_amount,
    wcc.registration_store_id AS registration_store_id
FROM with_country_and_staff AS wcc
JOIN country_rank_month AS crmr
  ON crmr.country_id = wcc.country_id
 AND crmr.month_start = wcc.month_start
 AND crmr.customer_id = wcc.customer_id
JOIN top_staff_details AS ts
  ON ts.customer_id = wcc.customer_id
 AND ts.month_start = wcc.month_start
JOIN top_store_details AS td
  ON td.customer_id = wcc.customer_id
 AND td.month_start = wcc.month_start
WHERE
    wcc.prev_month_amount IS NOT NULL
    AND (
        wcc.monthly_amount >= 3.0 * wcc.prev_month_amount
        OR wcc.monthly_amount >= 1.5 * wcc.country_avg_monthly_amount
    )
ORDER BY
    wcc.month_start,
    wcc.country_name,
    crmr.customer_country_month_rank,
    wcc.monthly_amount DESC,
    wcc.customer_id;