WITH monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(strftime('%Y-%m-01', p.p06)) AS month_start,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS month_amount,
        AVG(CAST(p.p05 AS REAL)) AS avg_check,
        COUNT(DISTINCT p.p03) AS distinct_staff_count
    FROM pay AS p
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 < '2006-01-01'
    GROUP BY
        p.p02,
        date(strftime('%Y-%m-01', p.p06))
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        city.d02 AS city_name,
        country.c01 AS country_id,
        country.c02 AS country_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS city ON city.d01 = a.e05
    JOIN cnt AS country ON country.c01 = city.d03
),
monthly_customer AS (
    SELECT
        cg.customer_id,
        cg.customer_name,
        cg.city_name,
        cg.country_id,
        cg.country_name,
        mp.month_start,
        COALESCE(mp.payment_count, 0) AS payment_count,
        COALESCE(mp.month_amount, 0.0) AS month_amount,
        COALESCE(mp.avg_check, 0.0) AS avg_check,
        COALESCE(mp.distinct_staff_count, 0) AS distinct_staff_count
    FROM customer_geo AS cg
    LEFT JOIN monthly_payments AS mp
      ON mp.customer_id = cg.customer_id
),
with_history AS (
    SELECT
        mc.*,
        (
            SELECT AVG(prev.month_amount)
            FROM monthly_payments AS prev
            WHERE prev.customer_id = mc.customer_id
              AND prev.month_start < mc.month_start
              AND prev.month_start >= date(mc.month_start, '-3 months')
        ) AS prev_3m_avg_amount
    FROM monthly_customer AS mc
),
country_month_stats AS (
    SELECT
        country_id,
        month_start,
        AVG(month_amount) AS country_avg_amount,
        COUNT(*) AS customer_count
    FROM monthly_customer
    GROUP BY country_id, month_start
),
country_ranks AS (
    SELECT
        wm.*,
        cms.country_avg_amount,
        cms.customer_count,
        RANK() OVER (
            PARTITION BY wm.country_id, wm.month_start
            ORDER BY wm.month_amount DESC
        ) AS country_month_rank,
        COUNT(*) OVER (
            PARTITION BY wm.country_id, wm.month_start
        ) AS customers_in_country_month
    FROM with_history AS wm
    JOIN country_month_stats AS cms
      ON cms.country_id = wm.country_id
     AND cms.month_start = wm.month_start
),
film_categories AS (
    SELECT
        p.p02 AS customer_id,
        date(strftime('%Y-%m-01', p.p06)) AS month_start,
        COUNT(DISTINCT flm.i12) AS category_count
    FROM pay AS p
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv AS i ON i.n01 = r.q03
    JOIN flm AS flm ON flm.i01 = i.n02
    WHERE flm.i12 IS NOT NULL
      AND p.p06 >= '2005-01-01'
      AND p.p06 < '2006-01-01'
    GROUP BY p.p02, date(strftime('%Y-%m-01', p.p06))
),
staff_concentration AS (
    SELECT
        p.p02 AS customer_id,
        date(strftime('%Y-%m-01', p.p06)) AS month_start,
        MAX(staff_payments) * 1.0 / SUM(staff_payments) AS same_staff_share,
        COUNT(DISTINCT stf.o07) AS store_count
    FROM (
        SELECT
            p2.p02,
            date(strftime('%Y-%m-01', p2.p06)) AS month_start,
            p2.p03 AS staff_id,
            COUNT(*) AS staff_payments
        FROM pay AS p2
        GROUP BY p2.p02, date(strftime('%Y-%m-01', p2.p06)), p2.p03
    ) AS sp
    JOIN pay AS p ON p.p02 = sp.p02
                  AND date(strftime('%Y-%m-01', p.p06)) = sp.month_start
                  AND p.p03 = sp.staff_id
    JOIN stf AS stf ON stf.o01 = p.p03
    GROUP BY p.p02, date(strftime('%Y-%m-01', p.p06))
),
scored AS (
    SELECT
        cr.customer_id,
        cr.customer_name,
        cr.city_name,
        cr.country_name,
        cr.month_start,
        cr.payment_count,
        cr.month_amount,
        cr.avg_check,
        cr.distinct_staff_count,
        cr.prev_3m_avg_amount,
        cr.country_avg_amount,
        cr.country_month_rank,
        cr.customers_in_country_month,
        fc.category_count,
        sc.same_staff_share,
        sc.store_count,
        cr.month_amount / NULLIF(cr.prev_3m_avg_amount, 0) AS growth_vs_prev_3m,
        CUME_DIST() OVER (
            PARTITION BY cr.country_id, cr.month_start
            ORDER BY cr.month_amount DESC
        ) AS country_volume_cume
    FROM country_ranks AS cr
    LEFT JOIN film_categories AS fc
      ON fc.customer_id = cr.customer_id
     AND fc.month_start = cr.month_start
    LEFT JOIN staff_concentration AS sc
      ON sc.customer_id = cr.customer_id
     AND sc.month_start = cr.month_start
)
SELECT
    customer_id,
    customer_name,
    city_name,
    country_name,
    strftime('%Y-%m', month_start) AS month,
    payment_count,
    ROUND(month_amount, 2) AS month_amount,
    ROUND(avg_check, 2) AS avg_check,
    ROUND(prev_3m_avg_amount, 2) AS prev_3m_avg_amount,
    ROUND(growth_vs_prev_3m, 2) AS growth_vs_prev_3m_ratio,
    ROUND(country_avg_amount, 2) AS country_avg_amount,
    ROUND(same_staff_share, 4) AS same_staff_share,
    store_count,
    category_count,
    country_month_rank AS risk_rank_in_country
FROM scored
WHERE prev_3m_avg_amount IS NOT NULL
  AND prev_3m_avg_amount > 0
  AND month_amount >= 3.0 * prev_3m_avg_amount
  AND country_volume_cume <= 0.05
ORDER BY
    country_name,
    month_start,
    risk_rank_in_country,
    month_amount DESC;