WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_day,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS daily_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT stf.o07) AS store_count,
        COUNT(DISTINCT p.p04) AS rental_count
    FROM pay AS p
    JOIN stf ON stf.o01 = p.p03
    GROUP BY p.p02, DATE(p.p06)
),
baseline_30d AS (
    SELECT
        d.*,
        (
            SELECT AVG(d2.daily_amount)
            FROM daily_payments AS d2
            WHERE d2.customer_id = d.customer_id
              AND d2.payment_day >= DATE(d.payment_day, '-30 days')
              AND d2.payment_day < d.payment_day
        ) AS avg_daily_amount_30d,
        (
            SELECT AVG(d2.payment_count * 1.0)
            FROM daily_payments AS d2
            WHERE d2.customer_id = d.customer_id
              AND d2.payment_day >= DATE(d.payment_day, '-30 days')
              AND d2.payment_day < d.payment_day
        ) AS avg_daily_count_30d
    FROM daily_payments AS d
),
country_ranked AS (
    SELECT
        b.*,
        cu.h03 || ' ' || cu.h04 AS customer_name,
        cu.h07 AS customer_status,
        adr.e01 AS address_id,
        cty.d02 AS city_name,
        cnt.c02 AS country_name,
        ROW_NUMBER() OVER (
            PARTITION BY cnt.c01, b.payment_day
            ORDER BY b.daily_amount DESC, b.payment_count DESC, b.customer_id
        ) AS country_amount_rank,
        COUNT(*) OVER (
            PARTITION BY cnt.c01, b.payment_day
        ) AS country_customers_count
    FROM baseline_30d AS b
    JOIN cus AS cu ON cu.h01 = b.customer_id
    JOIN adr ON adr.e01 = cu.h06
    JOIN cty ON cty.d01 = adr.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
last_payment_detail AS (
    SELECT
        p2.p02 AS customer_id,
        DATE(p2.p06) AS payment_day,
        p2.p03 AS last_staff_id,
        stf.o07 AS last_store_id
    FROM pay AS p2
    JOIN (
        SELECT
            p02 AS customer_id,
            DATE(p06) AS payment_day,
            MAX(p06) AS max_payment_ts
        FROM pay
        GROUP BY p02, DATE(p06)
    ) AS lp
      ON lp.customer_id = p2.p02
     AND lp.payment_day = DATE(p2.p06)
     AND lp.max_payment_ts = p2.p06
    JOIN stf ON stf.o01 = p2.p03
),
rental_stats AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_day,
        COUNT(DISTINCT p.p04) AS linked_rentals,
        SUM(CASE WHEN r.q05 IS NOT NULL AND r.q05 > DATE(r.q02, '+' || flm.i07 || ' days') THEN 1 ELSE 0 END) AS overdue_returns,
        COUNT(r.q01) AS total_rentals
    FROM pay AS p
    LEFT JOIN ren AS r ON r.q01 = p.p04
    LEFT JOIN inv ON inv.n01 = r.q03
    LEFT JOIN flm ON flm.i01 = inv.n02
    GROUP BY p.p02, DATE(p.p06)
)
SELECT
    cr.customer_id,
    cr.customer_name,
    cr.city_name,
    cr.country_name,
    cr.payment_day,
    cr.payment_count,
    ROUND(cr.daily_amount, 2) AS daily_amount,
    ROUND(cr.avg_daily_amount_30d, 2) AS avg_daily_amount_30d,
    ROUND(cr.avg_daily_count_30d, 2) AS avg_daily_count_30d,
    ROUND(cr.daily_amount - COALESCE(cr.avg_daily_amount_30d, 0), 2) AS amount_deviation,
    ROUND(cr.payment_count - COALESCE(cr.avg_daily_count_30d, 0), 2) AS count_deviation,
    lp.last_store_id,
    lp.last_staff_id,
    rs.linked_rentals,
    ROUND(1.0 * rs.overdue_returns / NULLIF(rs.total_rentals, 0), 4) AS overdue_return_share,
    cr.country_amount_rank,
    cr.country_customers_count
FROM country_ranked AS cr
LEFT JOIN last_payment_detail AS lp
    ON lp.customer_id = cr.customer_id
   AND lp.payment_day = cr.payment_day
LEFT JOIN rental_stats AS rs
    ON rs.customer_id = cr.customer_id
   AND rs.payment_day = cr.payment_day
WHERE cr.avg_daily_amount_30d IS NOT NULL
  AND cr.avg_daily_count_30d IS NOT NULL
  AND (
      cr.daily_amount >= 3 * cr.avg_daily_amount_30d
      OR cr.payment_count >= 3 * cr.avg_daily_count_30d
  )
ORDER BY
    cr.payment_day,
    cr.country_amount_rank,
    amount_deviation DESC,
    count_deviation DESC;