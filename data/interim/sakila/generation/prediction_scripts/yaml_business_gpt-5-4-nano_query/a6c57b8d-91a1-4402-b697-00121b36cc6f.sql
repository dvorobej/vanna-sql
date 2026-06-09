WITH payments_2005 AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p06 AS payment_datetime,
        strftime('%Y-%m', p.p06) AS payment_month
    FROM pay AS p
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 <  '2006-01-01'
),
customer_base AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        city.d01 AS city_id,
        city.d02 AS city_name,
        c.h02 AS home_store_id
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS city
        ON city.d01 = a.e05
    JOIN cnt
        ON cnt.c01 = city.d03
),
monthly_customer AS (
    SELECT
        p.customer_id,
        p.payment_month,
        COUNT(p.payment_id) AS payment_count,
        SUM(p.payment_amount) AS month_amount
    FROM payments_2005 AS p
    GROUP BY
        p.customer_id,
        p.payment_month
),
customer_with_personal_avg AS (
    SELECT
        mc.*,
        AVG(mc.month_amount) OVER (
            PARTITION BY mc.customer_id
        ) AS personal_avg_month_amount
    FROM monthly_customer AS mc
),
country_month_rank AS (
    SELECT
        cwp.*,
        cb.country_id,
        cb.country_name,
        cb.city_name,
        ROW_NUMBER() OVER (
            PARTITION BY cb.country_id, cwp.payment_month
            ORDER BY cwp.month_amount DESC
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY cb.country_id, cwp.payment_month
        ) AS cnt_in_country_month
    FROM customer_with_personal_avg AS cwp
    JOIN customer_base AS cb
      ON cb.customer_id = cwp.customer_id
),
top10_flag AS (
    SELECT
        cmr.*,
        CAST(cnt_in_country_month * 0.10 AS INTEGER) AS top10_base,
        CASE
            WHEN cnt_in_country_month * 0.10 > CAST(cnt_in_country_month * 0.10 AS INTEGER)
            THEN CAST(cnt_in_country_month * 0.10 AS INTEGER) + 1
            ELSE CAST(cnt_in_country_month * 0.10 AS INTEGER)
        END AS top10_cutoff
    FROM country_month_rank AS cmr
),
month_staff_top AS (
    SELECT
        p.customer_id,
        p.payment_month,
        p.staff_id,
        SUM(p.payment_amount) AS staff_month_amount,
        ROW_NUMBER() OVER (
            PARTITION BY p.customer_id, p.payment_month
            ORDER BY SUM(p.payment_amount) DESC, p.staff_id
        ) AS rn
    FROM payments_2005 AS p
    GROUP BY
        p.customer_id,
        p.payment_month,
        p.staff_id
),
final_rows AS (
    SELECT
        t10.customer_id,
        cb.country_name,
        cb.city_name,
        t10.payment_month,
        ROUND(t10.month_amount, 2) AS month_amount,
        t10.payment_count,
        ROUND(t10.month_amount - t10.personal_avg_month_amount, 2) AS deviation_from_personal_avg,
        t10.rn AS customer_country_month_rank,
        stf.o01 AS staff_id,
        stf.o02 || ' ' || stf.o03 AS staff_name,
        mst.staff_month_amount
    FROM top10_flag AS t10
    JOIN customer_base AS cb
      ON cb.customer_id = t10.customer_id
    JOIN month_staff_top AS mst
      ON mst.customer_id = t10.customer_id
     AND mst.payment_month = t10.payment_month
     AND mst.rn = 1
    JOIN stf
      ON stf.o01 = mst.staff_id
    WHERE t10.personal_avg_month_amount > 0
      AND t10.month_amount > 2.0 * t10.personal_avg_month_amount
      AND t10.rn <= t10.top10_cutoff
)
SELECT
    customer_id,
    country_name AS country,
    city_name AS city,
    payment_month AS month,
    month_amount,
    payment_count,
    deviation_from_personal_avg,
    customer_country_month_rank AS country_rank,
    staff_id,
    staff_name
FROM final_rows
ORDER BY
    payment_month,
    country,
    country_rank,
    month_amount DESC,
    customer_id;