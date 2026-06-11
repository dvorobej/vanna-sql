WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        co.c02 AS country_name,
        ct.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ct.d03
),
payments_enriched AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        date(p.p06) AS pay_date,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p03 AS staff_id,
        s.o07 AS staff_store_id,
        r.q01 AS rental_id,
        i.n01 AS inventory_id,
        fl.i11 AS mpaa_rating
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    LEFT JOIN ren AS r ON r.q01 = p.p04
    LEFT JOIN inv AS i ON i.n01 = r.q03
    LEFT JOIN flm AS fl ON fl.i01 = i.n01
),
daily_customer AS (
    SELECT
        pe.customer_id,
        cg.city_name,
        cg.country_name,
        pe.pay_date,
        COUNT(pe.payment_id) AS payment_count,
        SUM(pe.payment_amount) AS day_sum,
        MAX(pe.payment_amount) AS max_payment,
        COUNT(DISTINCT pe.staff_id) AS staff_count,
        COUNT(DISTINCT pe.staff_store_id) AS store_count,
        SUM(CASE WHEN pe.mpaa_rating IN ('R','NC-17') THEN pe.payment_amount ELSE 0 END) AS sum_r_rated,
        SUM(pe.payment_amount) AS total_day_sum
    FROM payments_enriched AS pe
    JOIN customer_geo AS cg ON cg.customer_id = pe.customer_id
    GROUP BY
        pe.customer_id,
        cg.city_name,
        cg.country_name,
        pe.pay_date
),
daily_with_avg AS (
    SELECT
        dc.*,
        (
            SELECT AVG(d2.total_day_sum)
            FROM daily_customer AS d2
            WHERE d2.customer_id = dc.customer_id
              AND d2.pay_date >= date(dc.pay_date, '-30 days')
              AND d2.pay_date < dc.pay_date
        ) AS avg_prev_30d
    FROM daily_customer AS dc
),
suspicious_days AS (
    SELECT
        d.*,
        CASE WHEN d.total_day_sum > 0 THEN d.sum_r_rated / d.total_day_sum ELSE 0 END AS rr_rated_payment_share,
        d.day_sum / NULLIF(d.avg_prev_30d, 0) AS ratio_over_avg
    FROM daily_with_avg AS d
    WHERE d.avg_prev_30d IS NOT NULL
      AND d.avg_prev_30d > 0
      AND d.day_sum >= 3 * d.avg_prev_30d
      AND (d.staff_count >= 3 OR d.store_count >= 3)
)
SELECT
    sd.country_name,
    sd.city_name,
    sd.pay_date AS payment_date,
    sd.payment_count,
    ROUND(sd.day_sum, 2) AS day_payment_sum,
    ROUND(sd.max_payment, 2) AS max_payment,
    ROUND(sd.rr_rated_payment_share, 4) AS rr_rated_payment_share,
    RANK() OVER (
        PARTITION BY sd.country_name
        ORDER BY sd.day_sum DESC
    ) AS day_rank_in_country
FROM suspicious_days AS sd
ORDER BY
    sd.country_name,
    day_rank_in_country,
    sd.pay_date,
    sd.city_name;