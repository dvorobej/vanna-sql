WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT r.q06) AS staff_rental_count,
        COUNT(DISTINCT c.h02) AS store_count
    FROM pay AS p
    JOIN ren AS r ON r.q01 = p.p04
    JOIN cus AS c ON c.h01 = p.p02
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
customer_history AS (
    SELECT
        mp.*,
        (
            SELECT AVG(h.monthly_amount)
            FROM (
                SELECT p2.p02, strftime('%Y-%m', p2.p06) AS m, SUM(p2.p05) AS monthly_amount
                FROM pay p2
                GROUP BY p2.p02, strftime('%Y-%m', p2.p06)
            ) AS h
            WHERE h.p02 = mp.customer_id AND h.m < mp.payment_month
        ) AS prev_avg_monthly_amount
    FROM monthly_payments AS mp
),
filtered_clients AS (
    SELECT
        ch.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        cnt.c01 AS country_id
    FROM customer_history AS ch
    JOIN cus AS c ON c.h01 = ch.customer_id
    JOIN adr ON adr.e01 = c.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
    WHERE ch.prev_avg_monthly_amount IS NOT NULL
      AND ch.monthly_amount >= 2.0 * ch.prev_avg_monthly_amount
      AND ch.payment_count >= 5
      AND (ch.staff_count >= 2 OR ch.store_count >= 2)
)
SELECT
    payment_month,
    customer_name,
    country,
    city,
    ROUND(monthly_amount, 2) AS monthly_amount,
    payment_count,
    ROUND(prev_avg_monthly_amount, 2) AS prev_avg_monthly_amount,
    RANK() OVER (
        PARTITION BY country_id, payment_month
        ORDER BY (monthly_amount - prev_avg_monthly_amount) DESC
    ) AS country_rank
FROM filtered_clients
ORDER BY
    country,
    payment_month,
    country_rank;