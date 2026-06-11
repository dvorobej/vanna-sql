WITH payments_2005 AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p06 AS payment_ts,
        date(p.p06, 'start of month') AS month_start,
        date(p.p06) AS payment_date
    FROM pay AS p
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 < '2006-01-01'
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cn.c02 AS country,
        cn.c01 AS country_id,
        ci.d02 AS city,
        c.h06 AS address_id
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS cn ON cn.c01 = ci.d03
),
monthly_customer AS (
    SELECT
        p.customer_id,
        p.month_start,
        SUM(p.payment_amount) AS monthly_amount,
        COUNT(*) AS payment_count
    FROM payments_2005 AS p
    GROUP BY
        p.customer_id,
        p.month_start
),
customer_avg AS (
    SELECT
        customer_id,
        AVG(monthly_amount) AS avg_monthly_amount
    FROM monthly_customer
    GROUP BY customer_id
),
monthly_country_ranks AS (
    SELECT
        mc.*,
        AVG(mc.monthly_amount) OVER (
            PARTITION BY cg.country_id, mc.month_start
        ) AS country_avg_monthly_amount,
        RANK() OVER (
            PARTITION BY cg.country_id, mc.month_start
            ORDER BY mc.monthly_amount DESC
        ) AS country_month_amount_rank,
        COUNT(*) OVER (
            PARTITION BY cg.country_id, mc.month_start
        ) AS country_month_customers
    FROM monthly_customer AS mc
    JOIN customer_geo AS cg
      ON cg.customer_id = mc.customer_id
),
top10_country AS (
    SELECT
        mcr.*,
        CASE
            WHEN mcr.country_month_amount_rank <= CAST(mcr.country_month_customers * 0.10 AS INTEGER)
            THEN 1
            ELSE 0
        END AS in_top_10_percent
    FROM monthly_country_ranks AS mcr
),
staff_top_by_month AS (
    SELECT
        p.customer_id,
        p.month_start,
        p.staff_id,
        SUM(p.payment_amount) AS staff_month_amount,
        ROW_NUMBER() OVER (
            PARTITION BY p.customer_id, p.month_start
            ORDER BY SUM(p.payment_amount) DESC, p.staff_id
        ) AS rn
    FROM payments_2005 AS p
    GROUP BY
        p.customer_id,
        p.month_start,
        p.staff_id
),
final_staff AS (
    SELECT
        st.customer_id,
        st.month_start,
        st.staff_id
    FROM staff_top_by_month AS st
    WHERE st.rn = 1
)
SELECT
    tc.customer_id,
    tcg.country,
    tcg.city,
    strftime('%Y-%m', tc.month_start) AS payment_month,
    ROUND(tc.monthly_amount, 2) AS payment_amount,
    tc.payment_count,
    ROUND(tc.monthly_amount - ca.avg_monthly_amount, 2) AS deviation_from_personal_avg,
    RANK() OVER (
        PARTITION BY tcg.country_id, tc.month_start
        ORDER BY tc.monthly_amount DESC
    ) AS country_month_customer_rank,
    fstaff.staff_id AS top_staff_id,
    sf.o02 || ' ' || sf.o03 AS top_staff_name
FROM top10_country AS tc
JOIN customer_geo AS tcg
  ON tcg.customer_id = tc.customer_id
JOIN customer_avg AS ca
  ON ca.customer_id = tc.customer_id
JOIN final_staff AS fstaff
  ON fstaff.customer_id = tc.customer_id
 AND fstaff.month_start = tc.month_start
JOIN stf AS sf
  ON sf.o01 = fstaff.staff_id
WHERE
    ca.avg_monthly_amount IS NOT NULL
    AND ca.avg_monthly_amount > 0
    AND tc.monthly_amount > 2.0 * ca.avg_monthly_amount
    AND tc.in_top_10_percent = 1
ORDER BY
    tc.month_start,
    tcg.country,
    tc.monthly_amount DESC,
    tc.customer_id;