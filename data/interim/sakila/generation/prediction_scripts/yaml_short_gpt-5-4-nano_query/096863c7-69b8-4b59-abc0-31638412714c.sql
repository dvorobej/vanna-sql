WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        cty.d02 AS city_name,
        co.c01 AS country_id,
        co.c02 AS country_name
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS cty
        ON cty.d01 = a.e05
    JOIN cnt AS co
        ON co.c01 = cty.d03
),
pay_daily AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s
        ON s.o01 = p.p03
    GROUP BY
        p.p02,
        date(p.p06)
),
customer_daily_extended AS (
    SELECT
        pd.*,
        cg.country_id,
        cg.country_name,
        cg.city_name,
        (
            SELECT AVG(prev.day_amount)
            FROM pay_daily AS prev
            WHERE prev.customer_id = pd.customer_id
              AND prev.payment_date >= date(pd.payment_date, '-30 day')
              AND prev.payment_date < pd.payment_date
        ) AS personal_avg_prev_30d
    FROM pay_daily AS pd
    JOIN customer_geo AS cg
        ON cg.customer_id = pd.customer_id
),
country_daily_avgs AS (
    SELECT
        cde.country_id,
        cde.payment_date,
        AVG(cde.day_amount) AS country_avg_day_amount
    FROM customer_daily_extended AS cde
    GROUP BY
        cde.country_id,
        cde.payment_date
),
scored AS (
    SELECT
        cde.customer_id,
        cde.country_id,
        cde.country_name,
        cde.city_name,
        cde.payment_date,
        cde.day_amount,
        cde.payment_count,
        cde.staff_count,
        cde.store_count,
        cde.personal_avg_prev_30d,
        cda.country_avg_day_amount,
        (cde.day_amount - cde.personal_avg_prev_30d) AS deviation_from_personal_avg,
        (cde.day_amount - cda.country_avg_day_amount) AS deviation_from_country_avg
    FROM customer_daily_extended AS cde
    JOIN country_daily_avgs AS cda
        ON cda.country_id = cde.country_id
       AND cda.payment_date = cde.payment_date
),
suspicious AS (
    SELECT
        s.*,
        DENSE_RANK() OVER (
            PARTITION BY s.country_id, s.payment_date
            ORDER BY s.day_amount DESC
        ) AS suspicious_amount_rank_in_country
    FROM scored AS s
    WHERE s.personal_avg_prev_30d IS NOT NULL
      AND s.personal_avg_prev_30d > 0
      AND s.day_amount > 3.0 * s.personal_avg_prev_30d
      AND s.day_amount > s.country_avg_day_amount
      AND (s.staff_count > 1 OR s.store_count > 1)
)
SELECT
    sy.customer_id,
    cg.first_name,
    cg.last_name,
    sy.country_name,
    sy.city_name,
    sy.payment_date,
    sy.day_amount AS day_sum,
    sy.payment_count,
    sy.deviation_from_personal_avg,
    sy.deviation_from_country_avg,
    sy.staff_count,
    sy.store_count,
    sy.suspicious_amount_rank_in_country
FROM suspicious AS sy
JOIN customer_geo AS cg
    ON cg.customer_id = sy.customer_id
ORDER BY
    sy.country_name,
    sy.payment_date,
    sy.suspicious_amount_rank_in_country,
    sy.day_sum DESC;