WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_fio,
        co.c02 AS country_name,
        ct.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a
      ON a.e01 = c.h06
    JOIN cty AS ct
      ON ct.d01 = a.e05
    JOIN cnt AS co
      ON co.c01 = ct.d03
),
monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS month_sum,
        MAX(CAST(p.p05 AS REAL)) AS max_payment,
        SUM(CASE WHEN CAST(p.p05 AS REAL) IS NOT NULL THEN 1 ELSE 0 END) AS payments_nonnull,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        (COUNT(*) - COUNT(DISTINCT p.p04)) AS dummy_inv_count
    FROM pay AS p
    JOIN stf AS s
      ON s.o01 = p.p03
    GROUP BY
        p.p02,
        date(p.p06, 'start of month')
),
monthly_with_prev AS (
    SELECT
        mp.*,
        AVG(month_sum) OVER (
            PARTITION BY customer_id
            ORDER BY month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_month_sum
    FROM monthly_payments AS mp
),
qualifying_months AS (
    SELECT
        mwp.*
    FROM monthly_with_prev AS mwp
    WHERE mwp.prev_avg_month_sum IS NOT NULL
      AND mwp.payment_count >= 3
      AND mwp.month_sum > 3.0 * mwp.prev_avg_month_sum
      AND (SELECT COUNT(DISTINCT date(p2.p06))
           FROM pay AS p2
           WHERE p2.p02 = mwp.customer_id
             AND date(p2.p06, 'start of month') = mwp.month_start) >= 3
),
final_calc AS (
    SELECT
        qm.customer_id,
        qm.month_start,
        cg.customer_fio,
        cg.country_name,
        cg.city_name,
        qm.payment_count,
        qm.month_sum,
        qm.max_payment,
        qm.max_payment * 1.0 / NULLIF(qm.month_sum, 0) AS max_payment_share,
        qm.staff_count,
        qm.store_count
    FROM qualifying_months AS qm
    JOIN customer_geo AS cg
      ON cg.customer_id = qm.customer_id
),
ranked AS (
    SELECT
        fc.*,
        RANK() OVER (
            PARTITION BY country_name, month_start
            ORDER BY month_sum DESC
        ) AS country_month_rank
    FROM final_calc AS fc
)
SELECT
    CAST(strftime('%Y-%m', month_start) AS TEXT) AS payment_month,
    customer_id,
    customer_fio,
    country_name,
    city_name,
    payment_count,
    ROUND(month_sum, 2) AS month_sum,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(max_payment_share, 4) AS max_payment_share,
    staff_count,
    store_count,
    country_month_rank
FROM ranked
ORDER BY
    country_name,
    payment_month,
    country_month_rank,
    customer_id;