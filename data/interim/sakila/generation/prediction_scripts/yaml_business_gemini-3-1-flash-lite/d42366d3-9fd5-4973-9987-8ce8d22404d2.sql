WITH monthly_customer_stats AS (
    SELECT
        p.p02 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        c.h02 AS home_store_id,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_sum,
        COUNT(*) AS monthly_count,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        SUM(CASE WHEN stf.o07 <> c.h02 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS off_home_store_share
    FROM pay p
    JOIN cus c ON p.p02 = c.h01
    JOIN adr ON c.h06 = adr.e01
    JOIN cty ON adr.e05 = cty.d01
    JOIN cnt ON cty.d03 = cnt.c01
    JOIN stf ON p.p03 = stf.o01
    GROUP BY 1, 2, 3, 4, 5, 6
),
history_and_country AS (
    SELECT
        mcs.*,
        AVG(mcs.monthly_sum) OVER (
            PARTITION BY mcs.customer_id 
            ORDER BY mcs.payment_month 
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS avg_prev_2_months,
        AVG(mcs.monthly_sum) OVER (
            PARTITION BY mcs.country_id, mcs.payment_month
        ) AS avg_country_month_sum,
        STDEV(mcs.monthly_sum) OVER (
            PARTITION BY mcs.country_id, mcs.payment_month
        ) AS stddev_country_month_sum,
        RANK() OVER (
            PARTITION BY mcs.country_id, mcs.payment_month 
            ORDER BY mcs.monthly_sum DESC
        ) AS country_rank
    FROM monthly_customer_stats mcs
),
suspicious_cases AS (
    SELECT *
    FROM history_and_country
    WHERE avg_prev_2_months IS NOT NULL
      AND monthly_sum > 2.0 * avg_prev_2_months
      AND monthly_sum > (avg_country_month_sum + 2.0 * stddev_country_month_sum)
)
SELECT
    customer_id,
    customer_name,
    country_name,
    payment_month,
    ROUND(monthly_sum, 2) AS monthly_sum,
    monthly_count,
    distinct_staff_count,
    ROUND(off_home_store_share, 4) AS off_home_store_share,
    country_rank
FROM suspicious_cases
ORDER BY payment_month, country_name, country_rank;