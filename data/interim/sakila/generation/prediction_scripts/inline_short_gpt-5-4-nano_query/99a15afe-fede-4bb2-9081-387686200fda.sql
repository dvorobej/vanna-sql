SELECT i.n02
        FROM inv i
        WHERE i.n01 = r.q03
    )
),
payments_with_late_flag AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        i.n03 AS store_id,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS payment_sum,
        SUM(CASE WHEN rf.is_late_return = 1 THEN 1 ELSE 0 END) AS late_return_payment_count
    FROM pay p
    JOIN ren r ON r.q01 = p.p04
    JOIN inv i ON i.n01 = r.q03
    JOIN (
        SELECT
            r2.q01 AS rental_id,
            CASE
                WHEN r2.q05 IS NULL THEN 0
                WHEN julianday(r2.q05) - julianday(r2.q02) > f.i07 THEN 1
                ELSE 0
            END AS is_late_return
        FROM ren r2
        JOIN inv ii ON ii.n01 = r2.q03
        JOIN flm f ON f.i01 = ii.n02
    ) rf ON rf.rental_id = r.q01
    GROUP BY
        p.p02,
        date(p.p06, 'start of month'),
        i.n03
),
final AS (
    SELECT
        pwh.customer_id,
        hg.country_name,
        hg.city_name,
        pwh.store_id,
        strftime('%Y-%m', pwh.month_start) AS payment_month,
        pwh.payment_sum,
        pwh.payment_count,
        COUNT(DISTINCT py.p03) AS staff_count_distinct,
        ROUND(
            1.0 * pwh.late_return_payment_count / NULLIF(pwh.payment_count, 0),
            4
        ) AS late_return_payment_share,
        st_prc.prc AS store_month_percent_rank
    FROM payments_with_late_flag pwh
    JOIN pay py
        ON py.p02 = pwh.customer_id
       AND date(py.p06, 'start of month') = pwh.month_start
       AND py.p04 IS NOT NULL
    JOIN home_geo hg ON hg.customer_id = pwh.customer_id
    LEFT JOIN store_country_month_percent_rank st_prc
        ON st_prc.customer_id = pwh.customer_id
       AND st_prc.month_start = pwh.month_start
       AND st_prc.store_id = pwh.store_id
    GROUP BY
        pwh.customer_id,
        hg.country_name,
        hg.city_name,
        pwh.store_id,
        pwh.month_start,
        pwh.payment_sum,
        pwh.payment_count,
        pwh.late_return_payment_count,
        st_prc.prc
),
customer_prev_avg AS (
    SELECT
        m.customer_id,
        m.month_start,
        m.payment_sum AS month_payment_sum,
        AVG(m.payment_sum) OVER (
            PARTITION BY m.customer_id
            ORDER BY m.month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_month_sum
    FROM monthly m
)
SELECT
    f.customer_id,
    f.country_name AS country,
    f.city_name AS city,
    f.store_id AS store_id,
    f.payment_month AS month,
    ROUND(f.payment_sum, 2) AS month_payment_sum,
    f.payment_count,
    f.staff_count_distinct AS distinct_staff_count,
    f.late_return_payment_share,
    RANK() OVER (
        PARTITION BY f.store_id, f.payment_month
        ORDER BY f.payment_sum DESC
    ) AS customer_store_month_rank
FROM final f
JOIN customer_prev_avg cpa
    ON cpa.customer_id = f.customer_id
   AND cpa.month_start = f.payment_month || '-01' /* join fix below */
WHERE 1=1
ORDER BY f.payment_month, f.store_id, f.payment_sum DESC;