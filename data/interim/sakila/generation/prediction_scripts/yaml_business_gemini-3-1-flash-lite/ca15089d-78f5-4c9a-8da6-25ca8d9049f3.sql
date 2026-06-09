WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS payment_month,
        COUNT(p.p01) AS payment_count,
        SUM(p.p05) AS total_amount,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        COUNT(DISTINCT DATE(p.p06)) AS distinct_days
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, strftime('%Y-%m', p.p06)
),
monthly_with_history AS (
    SELECT
        mp.*,
        AVG(mp.total_amount) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.payment_month
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS avg_prev_months
    FROM monthly_payments AS mp
),
suspicious_months AS (
    SELECT
        mwh.*,
        c.h03 AS first_name,
        c.h04 AS last_name,
        cty.d02 AS city,
        cnt.c02 AS country,
        cnt.c01 AS country_id
    FROM monthly_with_history AS mwh
    JOIN cus AS c ON c.h01 = mwh.customer_id
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
    WHERE mwh.total_amount >= 3 * mwh.avg_prev_months
      AND mwh.payment_count >= 3
      AND mwh.distinct_days >= 3
      AND (mwh.staff_count > 1 OR mwh.store_count > 1)
)
SELECT
    payment_month,
    first_name,
    last_name,
    country,
    city,
    payment_count,
    ROUND(total_amount, 2) AS total_amount,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(max_payment / total_amount, 4) AS max_payment_share,
    staff_count,
    store_count,
    RANK() OVER (
        PARTITION BY country_id, payment_month
        ORDER BY total_amount DESC
    ) AS country_rank
FROM suspicious_months
ORDER BY payment_month, country, country_rank;