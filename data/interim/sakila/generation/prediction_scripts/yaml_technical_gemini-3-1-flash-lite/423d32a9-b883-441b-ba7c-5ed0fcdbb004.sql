WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount,
        COUNT(p.p01) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT r.q06) AS rental_staff_count,
        COUNT(DISTINCT c.h02) AS store_count
    FROM pay AS p
    JOIN ren AS r ON r.q01 = p.p04
    JOIN cus AS c ON c.h01 = p.p02
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
historical_avg AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        SUM(p.p05) AS monthly_amount
    FROM pay AS p
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
monthly_with_history AS (
    SELECT
        mp.*,
        (
            SELECT AVG(h.monthly_amount)
            FROM historical_avg AS h
            WHERE h.customer_id = mp.customer_id
              AND h.payment_month < mp.payment_month
        ) AS prev_avg_amount
    FROM monthly_payments AS mp
),
filtered_months AS (
    SELECT
        mwh.*,
        (mwh.monthly_amount - mwh.prev_avg_amount) AS deviation
    FROM monthly_with_history AS mwh
    WHERE mwh.prev_avg_amount IS NOT NULL
      AND mwh.monthly_amount >= 2.0 * mwh.prev_avg_amount
      AND mwh.payment_count >= 5
      AND (mwh.staff_count >= 2 OR mwh.store_count >= 2)
),
ranked_customers AS (
    SELECT
        fm.*,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city,
        RANK() OVER (
            PARTITION BY cnt.c01, fm.payment_month
            ORDER BY fm.deviation DESC
        ) AS country_rank
    FROM filtered_months AS fm
    JOIN cus AS c ON c.h01 = fm.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
)
SELECT
    payment_month,
    customer_name,
    country,
    city,
    ROUND(monthly_amount, 2) AS monthly_amount,
    payment_count,
    ROUND(prev_avg_amount, 2) AS prev_avg_amount,
    ROUND(deviation, 2) AS deviation,
    staff_count,
    store_count,
    country_rank
FROM ranked_customers
ORDER BY
    country,
    payment_month,
    country_rank;