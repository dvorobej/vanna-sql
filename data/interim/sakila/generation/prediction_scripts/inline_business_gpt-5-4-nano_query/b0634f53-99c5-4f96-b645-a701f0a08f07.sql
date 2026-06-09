WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c01 AS customer_country_id,
        cnt.c02 AS customer_country_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS city ON city.d01 = a.e05
    JOIN cnt ON cnt.c01 = city.d03
),
payments_2005 AS (
    SELECT
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        s.o07 AS staff_store_id,
        p.p06 AS payment_ts,
        DATE(p.p06) AS payment_date,
        CAST(p.p05 AS REAL) AS payment_amount
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    WHERE p.p06 >= '2005-01-01' AND p.p06 < '2006-01-01'
),
daily_base AS (
    SELECT
        p.customer_id,
        p.payment_date,
        COUNT(*) AS payment_count,
        SUM(p.payment_amount) AS day_amount,
        COUNT(DISTINCT p.staff_id) AS distinct_staff_count,
        COUNT(DISTINCT p.staff_store_id) AS distinct_store_count
    FROM payments_2005 AS p
    GROUP BY p.customer_id, p.payment_date
),
daily_with_staff_store_countries AS (
    SELECT
        p.customer_id,
        p.payment_date,
        group_concat(DISTINCT ms.country_name) AS store_countries_in_day,
        MAX(CASE WHEN ms.country_name <> cg.customer_country_name THEN 1 ELSE 0 END) AS has_foreign_store_payment
    FROM payments_2005 AS p
    JOIN customer_geo AS cg
      ON cg.customer_id = p.customer_id
    JOIN sto AS st
      ON st.j01 = p.staff_store_id
    JOIN adr AS a
      ON a.e01 = st.j03
    JOIN cty AS city
      ON city.d01 = a.e05
    JOIN cnt AS ms
      ON ms.c01 = city.d03
    GROUP BY p.customer_id, p.payment_date
),
daily_with_history AS (
    SELECT
        db.customer_id,
        db.payment_date,
        db.payment_count,
        db.day_amount,
        db.distinct_staff_count,
        db.distinct_store_count,
        dss.store_countries_in_day,
        dss.has_foreign_store_payment,
        (
            SELECT AVG(db2.day_amount)
            FROM daily_base AS db2
            WHERE db2.customer_id = db.customer_id
              AND db2.payment_date >= date(db.payment_date, '-30 day')
              AND db2.payment_date < db.payment_date
        ) AS avg_daily_amount_prev_30d
    FROM daily_base AS db
    JOIN daily_with_staff_store_countries AS dss
      ON dss.customer_id = db.customer_id
     AND dss.payment_date = db.payment_date
),
suspicious_days AS (
    SELECT
        dwh.*,
        (dwh.day_amount / NULLIF(dwh.avg_daily_amount_prev_30d, 0)) AS exceed_ratio
    FROM daily_with_history AS dwh
    WHERE dwh.avg_daily_amount_prev_30d IS NOT NULL
      AND dwh.avg_daily_amount_prev_30d > 0
      AND dwh.payment_count >= 3
      AND dwh.day_amount >= 2.0 * dwh.avg_daily_amount_prev_30d
      AND dwh.distinct_store_count >= 2
      AND dwh.has_foreign_store_payment = 1
),
ranked AS (
    SELECT
        sd.*,
        cg.customer_name,
        cg.customer_country_name,
        RANK() OVER (
            PARTITION BY cg.customer_country_name
            ORDER BY sd.exceed_ratio DESC, sd.day_amount DESC, sd.payment_date
        ) AS suspicious_rank_within_country
    FROM suspicious_days AS sd
    JOIN customer_geo AS cg
      ON cg.customer_id = sd.customer_id
)
SELECT
    r.customer_id,
    r.customer_name,
    r.payment_date,
    r.customer_country_name AS customer_country,
    r.payment_count,
    ROUND(r.day_amount, 2) AS day_amount,
    ROUND(r.avg_daily_amount_prev_30d, 2) AS avg_daily_amount_prev_30d,
    r.distinct_staff_count AS used_staff_count,
    r.distinct_store_count AS used_store_count,
    r.store_countries_in_day AS store_countries_in_day,
    r.suspicious_rank_within_country
FROM ranked AS r
ORDER BY
    r.customer_country,
    r.suspicious_rank_within_country,
    r.payment_date,
    r.customer_id;