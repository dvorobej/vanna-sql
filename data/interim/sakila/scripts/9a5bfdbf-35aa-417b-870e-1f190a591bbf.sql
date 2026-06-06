WITH payment_details AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        p.p05 AS amount,
        p.p03 AS staff_id,
        st.o07 AS store_id,
        cu.h03 || ' ' || cu.h04 AS customer_full_name,
        cust_cnt.c01 AS customer_country_id,
        cust_cnt.c02 AS customer_country,
        staff_cnt.c01 AS staff_store_country_id
    FROM pay AS p
    JOIN cus AS cu ON cu.h01 = p.p02
    JOIN adr AS cust_adr ON cust_adr.e01 = cu.h06
    JOIN cty AS cust_cty ON cust_cty.d01 = cust_adr.e05
    JOIN cnt AS cust_cnt ON cust_cnt.c01 = cust_cty.d03
    JOIN stf AS st ON st.o01 = p.p03
    JOIN sto AS store ON store.j01 = st.o07
    JOIN adr AS store_adr ON store_adr.e01 = store.j03
    JOIN cty AS store_cty ON store_cty.d01 = store_adr.e05
    JOIN cnt AS staff_cnt ON staff_cnt.c01 = store_cty.d03
),
monthly_payments AS (
    SELECT
        customer_id,
        payment_month,
        customer_full_name,
        customer_country,
        COUNT(*) AS payment_count,
        SUM(amount) AS monthly_amount,
        COUNT(DISTINCT staff_id) AS distinct_staff_count,
        COUNT(DISTINCT store_id) AS distinct_store_count,
        MAX(CASE WHEN staff_store_country_id <> customer_country_id THEN 1 ELSE 0 END) AS has_foreign_store_payment
    FROM payment_details
    GROUP BY
        customer_id,
        payment_month,
        customer_full_name,
        customer_country
),
monthly_with_history AS (
    SELECT
        mp.*,
        AVG(monthly_amount) OVER (
            PARTITION BY customer_id
            ORDER BY payment_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS historical_avg_monthly_amount
    FROM monthly_payments AS mp
),
eligible_customers AS (
    SELECT
        payment_month,
        customer_full_name,
        customer_country,
        payment_count,
        monthly_amount,
        historical_avg_monthly_amount,
        monthly_amount - historical_avg_monthly_amount AS deviation_from_historical_avg,
        distinct_staff_count,
        distinct_store_count
    FROM monthly_with_history
    WHERE payment_count >= 5
      AND historical_avg_monthly_amount IS NOT NULL
      AND monthly_amount > historical_avg_monthly_amount * 2
      AND has_foreign_store_payment = 1
)
SELECT
    payment_month AS month,
    customer_full_name,
    customer_country,
    payment_count,
    ROUND(monthly_amount, 2) AS payment_amount,
    ROUND(deviation_from_historical_avg, 2) AS deviation_from_historical_avg,
    distinct_staff_count,
    distinct_store_count,
    RANK() OVER (
        PARTITION BY payment_month
        ORDER BY deviation_from_historical_avg DESC
    ) AS customer_rank_in_month
FROM eligible_customers
ORDER BY
    payment_month,
    customer_rank_in_month,
    customer_full_name;