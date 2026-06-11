WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        co.c02 AS customer_country_name
    FROM cus c
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ci ON ci.d01 = a.e05
    JOIN cnt co ON co.c01 = ci.d03
),
payments_2005 AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        p.p03 AS staff_id,
        p.p05 AS payment_amount,
        s.o07 AS staff_store_id,
        st.j01 AS staff_store_id_check,
        co_s.c02 AS staff_store_country_name
    FROM pay p
    JOIN stf s ON s.o01 = p.p03
    JOIN sto st ON st.j01 = s.o07
    JOIN adr a_s ON a_s.e01 = st.j03
    JOIN cty ci_s ON ci_s.d01 = a_s.e05
    JOIN cnt co_s ON co_s.c01 = ci_s.d03
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 <  '2006-01-01'
),
daily_customer AS (
    SELECT
        p.customer_id,
        p.payment_date,
        COUNT(*) AS payment_count,
        SUM(p.payment_amount) AS day_amount,
        COUNT(DISTINCT p.staff_id) AS distinct_staff_count,
        COUNT(DISTINCT p.staff_store_id) AS distinct_store_count,
        SUM(CASE WHEN p.staff_store_country_name <> cg.customer_country_name THEN 1 ELSE 0 END) AS foreign_country_payment_count
    FROM payments_2005 p
    JOIN customer_geo cg ON cg.customer_id = p.customer_id
    GROUP BY
        p.customer_id,
        p.payment_date
),
with_prev_avg AS (
    SELECT
        dc.*,
        (
            SELECT AVG(dc2.day_amount)
            FROM daily_customer dc2
            WHERE dc2.customer_id = dc.customer_id
              AND dc2.payment_date >= DATE(dc.payment_date, '-30 days')
              AND dc2.payment_date <  dc.payment_date
        ) AS avg_daily_amount_prev_30d
    FROM daily_customer dc
),
suspicious_days AS (
    SELECT
        wp.*,
        (wp.day_amount / NULLIF(wp.avg_daily_amount_prev_30d, 0)) AS exceed_ratio
    FROM with_prev_avg wp
    WHERE wp.avg_daily_amount_prev_30d IS NOT NULL
      AND wp.avg_daily_amount_prev_30d > 0
      AND wp.payment_count >= 3
      AND wp.day_amount >= 2 * wp.avg_daily_amount_prev_30d
      AND wp.distinct_store_count >= 2
      AND wp.foreign_country_payment_count >= 1
)
SELECT
    sd.customer_id,
    cg.customer_name,
    sd.payment_date,
    cg.customer_country_name AS customer_country,
    sd.payment_count,
    ROUND(sd.day_amount, 2) AS day_payment_amount,
    ROUND(sd.avg_daily_amount_prev_30d, 2) AS avg_daily_amount_prev_30d,
    sd.distinct_staff_count,
    sd.distinct_store_count,
    (
        SELECT GROUP_CONCAT(DISTINCT ps.staff_store_country_name)
        FROM payments_2005 ps
        WHERE ps.customer_id = sd.customer_id
          AND ps.payment_date = sd.payment_date
    ) AS store_countries_in_that_day,
    RANK() OVER (
        PARTITION BY cg.customer_country_name
        ORDER BY (sd.day_amount / sd.avg_daily_amount_prev_30d) DESC, sd.day_amount DESC
    ) AS suspicious_rank_in_customer_country
FROM suspicious_days sd
JOIN customer_geo cg
  ON cg.customer_id = sd.customer_id
ORDER BY
    suspicious_rank_in_customer_country,
    sd.day_amount DESC,
    sd.payment_date,
    sd.customer_id;