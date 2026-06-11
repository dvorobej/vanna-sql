WITH monthly_payments AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_fio,
        co.c02 AS country_name,
        ci.d02 AS city_name,
        date(p.p06, 'start of month') AS month_start,
        COUNT(p.p01) AS payment_count,
        SUM(p.p05) AS total_amount,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT s.o07) AS distinct_store_count,
        COUNT(DISTINCT date(p.p06)) AS distinct_payment_days
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
    JOIN stf AS s ON s.o01 = p.p03
    WHERE p.p04 IS NULL OR p.p04 IS NOT NULL
    GROUP BY
        c.h01, c.h03, c.h04,
        co.c02, ci.d02,
        date(p.p06, 'start of month')
),
with_prev_avg AS (
    SELECT
        mp.*,
        (
            SELECT AVG(mp2.total_amount)
            FROM monthly_payments mp2
            WHERE mp2.customer_id = mp.customer_id
              AND mp2.month_start < mp.month_start
        ) AS prev_avg_monthly_amount
    FROM monthly_payments mp
),
qualified AS (
    SELECT
        wpa.*
    FROM with_prev_avg wpa
    WHERE wpa.prev_avg_monthly_amount IS NOT NULL
      AND wpa.total_amount >= 3 * wpa.prev_avg_monthly_amount
      AND wpa.payment_count >= 3
      AND wpa.distinct_payment_days >= 3
      AND (wpa.distinct_staff_count >= 2 OR wpa.distinct_store_count >= 2)
),
ranked AS (
    SELECT
        q.*,
        RANK() OVER (
            PARTITION BY country_name, month_start
            ORDER BY total_amount DESC
        ) AS country_month_amount_rank
    FROM qualified q
)
SELECT
    strftime('%Y-%m', r.month_start) AS payment_month,
    r.customer_fio,
    r.country_name AS country,
    r.city_name AS city,
    r.payment_count,
    ROUND(r.total_amount, 2) AS monthly_total_amount,
    ROUND(r.max_payment, 2) AS max_payment,
    ROUND(
        CASE WHEN r.total_amount != 0 THEN r.max_payment / r.total_amount ELSE 0 END,
        4
    ) AS max_payment_share_in_month,
    r.distinct_staff_count AS distinct_staff_count,
    r.distinct_store_count AS distinct_store_count,
    r.country_month_amount_rank
FROM ranked r
ORDER BY
    r.country_name,
    r.month_start,
    r.country_month_amount_rank,
    r.customer_id;