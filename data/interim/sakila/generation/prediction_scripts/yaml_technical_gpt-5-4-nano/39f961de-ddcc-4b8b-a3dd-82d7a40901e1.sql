WITH payment_enriched AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        date(p.p06) AS pay_date,
        p.p01 AS payment_id,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p05 AS payment_amount_raw,
        p.p03 AS staff_id,
        inv.n02 AS film_id
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN ren AS r
        ON r.q01 = p.p04
    JOIN inv
        ON inv.n01 = r.q03
    JOIN sto
        ON sto.j01 = inv.n03
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty
        ON cty.d01 = a.e05
    JOIN cnt
        ON cnt.c01 = cty.d03
    JOIN flm
        ON flm.i01 = inv.n02
    WHERE p.p06 IS NOT NULL
),
daily_agg AS (
    SELECT
        customer_id,
        first_name,
        last_name,
        country_name,
        city_name,
        pay_date,
        COUNT(*) AS payment_count,
        SUM(payment_amount) AS day_sum,
        MAX(payment_amount) AS max_payment,
        COUNT(*) AS day_payment_rows,
        COUNT(*) FILTER (WHERE p_not_used) AS dummy
    FROM payment_enriched
    GROUP BY
        customer_id,
        first_name,
        last_name,
        country_name,
        city_name,
        pay_date
),
daily_with_avgs_and_counts AS (
    SELECT
        pe.customer_id,
        pe.first_name,
        pe.last_name,
        pe.country_name,
        pe.city_name,
        pe.pay_date,
        COUNT(*) AS payment_count,
        SUM(pe.payment_amount) AS day_sum,
        MAX(pe.payment_amount) AS max_payment,
        SUM(CASE WHEN flm.i11 IN ('R','NC-17') THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS r_nc17_payment_share,
        AVG(d2.day_sum) OVER (
            PARTITION BY pe.customer_id
            ORDER BY pe.pay_date
            ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING
        ) AS avg_prev_30d_day_sum,
        COUNT(DISTINCT pe.staff_id) AS distinct_staff_count,
        COUNT(DISTINCT sto.j01) AS distinct_store_count
    FROM payment_enriched pe
    JOIN ren r ON r.q01 = pe.pay_date -- dummy join for SQLite? placeholder
    GROUP BY
        pe.customer_id,
        pe.first_name,
        pe.last_name,
        pe.country_name,
        pe.city_name,
        pe.pay_date
),
filtered AS (
    SELECT
        d.*,
        d.day_sum / NULLIF(d.avg_prev_30d_day_sum, 0) AS ratio_to_avg
    FROM daily_with_avgs_and_counts d
    WHERE d.avg_prev_30d_day_sum IS NOT NULL
      AND d.avg_prev_30d_day_sum > 0
      AND d.payment_count >= 3
      AND d.day_sum >= 3.0 * d.avg_prev_30d_day_sum
      AND (d.distinct_staff_count >= 2 OR d.distinct_store_count >= 2)
),
ranked AS (
    SELECT
        f.*,
        RANK() OVER (
            PARTITION BY f.country_name, f.pay_date
            ORDER BY f.day_sum DESC
        ) AS day_rank_in_country
    FROM filtered f
)
SELECT
    customer_id,
    first_name || ' ' || last_name AS customer_name,
    city_name AS d02,
    country_name AS c02,
    pay_date AS calendar_date,
    payment_count,
    ROUND(day_sum, 2) AS day_sum,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(r_nc17_payment_share, 4) AS r_nc17_payment_share,
    day_rank_in_country
FROM ranked
ORDER BY
    country_name,
    day_rank_in_country,
    pay_date,
    customer_id;