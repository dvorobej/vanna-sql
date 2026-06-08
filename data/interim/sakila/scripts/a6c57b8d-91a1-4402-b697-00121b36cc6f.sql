WITH
payments_2005 AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        p.p05 AS payment_amount,
        p.p06 AS payment_date,
        strftime('%Y-%m', p.p06) AS payment_month
    FROM pay AS p
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 <  '2006-01-01'
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS customer_first_name,
        c.h04 AS customer_last_name,
        a.e01 AS address_id,
        city.d01 AS city_id,
        city.d02 AS city_name,
        country.c01 AS country_id,
        country.c02 AS country_name
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS city
        ON city.d01 = a.e05
    JOIN cnt AS country
        ON country.c01 = city.d03
),
client_month AS (
    SELECT
        cg.customer_id,
        cg.customer_first_name,
        cg.customer_last_name,
        cg.city_id,
        cg.city_name,
        cg.country_id,
        cg.country_name,
        p.payment_month,
        SUM(p.payment_amount) AS monthly_payment_sum,
        COUNT(*) AS monthly_payment_count
    FROM payments_2005 AS p
    JOIN customer_geo AS cg
        ON cg.customer_id = p.customer_id
    GROUP BY
        cg.customer_id,
        cg.customer_first_name,
        cg.customer_last_name,
        cg.city_id,
        cg.city_name,
        cg.country_id,
        cg.country_name,
        p.payment_month
),
client_personal_avg AS (
    SELECT
        customer_id,
        AVG(monthly_payment_sum) AS personal_avg_monthly_sum,
        AVG(monthly_payment_count) AS personal_avg_monthly_count
    FROM client_month
    GROUP BY customer_id
),
country_month_avg AS (
    SELECT
        country_id,
        payment_month,
        AVG(monthly_payment_sum) AS country_avg_monthly_sum,
        AVG(monthly_payment_count) AS country_avg_monthly_count
    FROM client_month
    GROUP BY
        country_id,
        payment_month
),
ranked_client_month AS (
    SELECT
        cm.customer_id,
        cm.customer_first_name,
        cm.customer_last_name,
        cm.city_id,
        cm.city_name,
        cm.country_id,
        cm.country_name,
        cm.payment_month,
        cm.monthly_payment_sum,
        cm.monthly_payment_count,
        cpa.personal_avg_monthly_sum,
        cpa.personal_avg_monthly_count,
        cma.country_avg_monthly_sum,
        cma.country_avg_monthly_count,
        cm.monthly_payment_sum - cpa.personal_avg_monthly_sum AS deviation_from_personal_avg,
        RANK() OVER (
            PARTITION BY cm.country_id, cm.payment_month
            ORDER BY cm.monthly_payment_sum DESC
        ) AS country_rank,
        COUNT(*) OVER (
            PARTITION BY cm.country_id, cm.payment_month
        ) AS country_customer_count
    FROM client_month AS cm
    JOIN client_personal_avg AS cpa
        ON cpa.customer_id = cm.customer_id
    JOIN country_month_avg AS cma
        ON cma.country_id = cm.country_id
       AND cma.payment_month = cm.payment_month
),
staff_month AS (
    SELECT
        p.customer_id,
        p.payment_month,
        p.staff_id,
        s.o02 AS staff_first_name,
        s.o03 AS staff_last_name,
        s.o06 AS staff_email,
        SUM(p.payment_amount) AS staff_payment_sum,
        COUNT(*) AS staff_payment_count
    FROM payments_2005 AS p
    JOIN stf AS s
        ON s.o01 = p.staff_id
    GROUP BY
        p.customer_id,
        p.payment_month,
        p.staff_id,
        s.o02,
        s.o03,
        s.o06
),
top_staff AS (
    SELECT
        sm.*,
        ROW_NUMBER() OVER (
            PARTITION BY sm.customer_id, sm.payment_month
            ORDER BY sm.staff_payment_sum DESC, sm.staff_payment_count DESC, sm.staff_id
        ) AS staff_rank
    FROM staff_month AS sm
)
SELECT
    r.customer_id,
    r.customer_first_name || ' ' || r.customer_last_name AS customer_name,
    r.country_name,
    r.city_name,
    r.payment_month,
    ROUND(r.monthly_payment_sum, 2) AS monthly_payment_sum,
    r.monthly_payment_count,
    ROUND(r.personal_avg_monthly_sum, 2) AS personal_avg_monthly_sum,
    ROUND(r.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
    ROUND(r.country_avg_monthly_sum, 2) AS country_avg_monthly_sum,
    ROUND(r.country_avg_monthly_count, 2) AS country_avg_monthly_payment_count,
    r.country_rank,
    r.country_customer_count,
    ts.staff_id,
    ts.staff_first_name || ' ' || ts.staff_last_name AS top_staff_name,
    ts.staff_email,
    ROUND(ts.staff_payment_sum, 2) AS top_staff_payment_sum,
    ts.staff_payment_count AS top_staff_payment_count
FROM ranked_client_month AS r
JOIN top_staff AS ts
    ON ts.customer_id = r.customer_id
   AND ts.payment_month = r.payment_month
   AND ts.staff_rank = 1
WHERE r.monthly_payment_sum > r.personal_avg_monthly_sum * 2
  AND r.country_rank <= ((r.country_customer_count + 9) / 10)
ORDER BY
    r.payment_month,
    r.country_name,
    r.country_rank,
    r.monthly_payment_sum DESC,
    r.customer_id;