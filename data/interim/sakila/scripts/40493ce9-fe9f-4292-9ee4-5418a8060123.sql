WITH prev_monthly AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS pay_month,
        SUM(p.p05) AS month_amount,
        COUNT(*) AS month_count
    FROM pay AS p
    WHERE p.p06 < '2005-07-01'
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
prev_avg AS (
    SELECT
        customer_id,
        SUM(month_amount) AS prev_total_amount,
        SUM(month_count) AS prev_total_count,
        AVG(month_amount) AS prev_avg_month_amount,
        AVG(month_count) AS prev_avg_month_count
    FROM prev_monthly
    GROUP BY customer_id
),
july AS (
    SELECT
        p.p02 AS customer_id,
        SUM(p.p05) AS july_amount,
        COUNT(*) AS july_count,
        SUM(CASE WHEN st.o07 <> c.h02 THEN 1 ELSE 0 END) AS foreign_store_count,
        MAX(CASE WHEN st.o07 <> c.h02 THEN p.p06 END) AS last_foreign_store_payment_date
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN stf AS st
        ON st.o01 = p.p03
    WHERE p.p06 >= '2005-07-01'
      AND p.p06 < '2005-08-01'
    GROUP BY p.p02
),
qualified AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS customer_first_name,
        c.h04 AS customer_last_name,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        j.july_amount,
        j.july_count,
        pa.prev_total_amount,
        pa.prev_total_count,
        pa.prev_avg_month_amount,
        pa.prev_avg_month_count,
        CAST(j.foreign_store_count AS REAL) / NULLIF(j.july_count, 0) AS foreign_store_operation_share,
        j.last_foreign_store_payment_date,
        j.july_amount - pa.prev_avg_month_amount AS july_amount_growth,
        j.july_count - pa.prev_avg_month_count AS july_count_growth
    FROM july AS j
    JOIN prev_avg AS pa
        ON pa.customer_id = j.customer_id
    JOIN cus AS c
        ON c.h01 = j.customer_id
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty
        ON cty.d01 = a.e05
    JOIN cnt
        ON cnt.c01 = cty.d03
    WHERE j.july_amount > 2 * pa.prev_avg_month_amount
      AND j.july_count > 2 * pa.prev_avg_month_count
      AND j.foreign_store_count > 0
)
SELECT
    customer_id,
    customer_first_name,
    customer_last_name,
    country_name,
    city_name,
    july_amount,
    july_count,
    prev_total_amount,
    prev_total_count,
    prev_avg_month_amount,
    prev_avg_month_count,
    foreign_store_operation_share,
    last_foreign_store_payment_date,
    july_amount_growth,
    july_count_growth,
    RANK() OVER (
        PARTITION BY country_id
        ORDER BY july_amount_growth DESC, customer_id
    ) AS country_growth_rank
FROM qualified
ORDER BY country_name, country_growth_rank, customer_id;