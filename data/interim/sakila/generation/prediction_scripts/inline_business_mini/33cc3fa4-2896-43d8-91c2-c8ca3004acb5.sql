WITH payment_detail AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        p.p04 AS rental_id,
        p.p05 AS amount,
        p.p06 AS payment_ts,
        DATE(p.p06) AS payment_day,
        julianday(p.p06) AS payment_jd,
        r.q03 AS inventory_id,
        r.q05 AS return_ts,
        stf.o07 AS staff_store_id
    FROM pay AS p
    JOIN stf AS stf
      ON stf.o01 = p.p03
    LEFT JOIN ren AS r
      ON r.q01 = p.p04
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        city.d02 AS city_name,
        country.c02 AS country_name
    FROM cus AS c
    JOIN adr AS a
      ON a.e01 = c.h06
    JOIN cty AS city
      ON city.d01 = a.e05
    JOIN cnt AS country
      ON country.c01 = city.d03
),
daily_customer AS (
    SELECT
        pd.customer_id,
        pd.payment_day,
        COUNT(*) AS payment_count,
        SUM(CAST(pd.amount AS REAL)) AS daily_amount,
        COUNT(DISTINCT pd.staff_id) AS distinct_staff_count,
        COUNT(DISTINCT pd.staff_store_id) AS distinct_store_count,
        COUNT(DISTINCT pd.rental_id) AS rental_count
    FROM payment_detail AS pd
    GROUP BY
        pd.customer_id,
        pd.payment_day
),
daily_last_payment AS (
    SELECT
        pd.customer_id,
        pd.payment_day,
        pd.payment_id,
        pd.staff_id,
        pd.staff_store_id,
        pd.payment_ts,
        ROW_NUMBER() OVER (
            PARTITION BY pd.customer_id, pd.payment_day
            ORDER BY pd.payment_jd DESC, pd.payment_id DESC
        ) AS rn
    FROM payment_detail AS pd
),
daily_last_payment_one AS (
    SELECT
        customer_id,
        payment_day,
        payment_id AS last_payment_id,
        staff_id AS last_staff_id,
        staff_store_id AS last_store_id,
        payment_ts AS last_payment_ts
    FROM daily_last_payment
    WHERE rn = 1
),
customer_daily_history AS (
    SELECT
        dc.*,
        (
            SELECT AVG(prev.daily_amount)
            FROM daily_customer AS prev
            WHERE prev.customer_id = dc.customer_id
              AND prev.payment_day >= DATE(dc.payment_day, '-30 days')
              AND prev.payment_day < dc.payment_day
        ) AS prev30_avg_amount,
        (
            SELECT AVG(prev.payment_count * 1.0)
            FROM daily_customer AS prev
            WHERE prev.customer_id = dc.customer_id
              AND prev.payment_day >= DATE(dc.payment_day, '-30 days')
              AND prev.payment_day < dc.payment_day
        ) AS prev30_avg_count,
        (
            SELECT COUNT(*)
            FROM daily_customer AS prev
            WHERE prev.customer_id = dc.customer_id
              AND prev.payment_day >= DATE(dc.payment_day, '-30 days')
              AND prev.payment_day < dc.payment_day
        ) AS prev30_days_count
    FROM daily_customer AS dc
),
late_rentals AS (
    SELECT
        r.q04 AS customer_id,
        COUNT(*) AS rental_count,
        SUM(CASE
                WHEN r.q05 IS NOT NULL AND julianday(r.q05) > julianday(r.q02, '+7 days') THEN 1
                ELSE 0
            END) AS late_return_count
    FROM ren AS r
    GROUP BY r.q04
),
country_day_rank AS (
    SELECT
        dch.customer_id,
        dch.payment_day,
        cg.country_name,
        RANK() OVER (
            PARTITION BY cg.country_name, dch.payment_day
            ORDER BY dch.daily_amount DESC, dch.payment_count DESC, dch.customer_id
        ) AS country_day_amount_rank
    FROM customer_daily_history AS dch
    JOIN customer_geo AS cg
      ON cg.customer_id = dch.customer_id
)
SELECT
    dch.customer_id,
    cg.first_name || ' ' || cg.last_name AS customer_name,
    cg.country_name,
    cg.city_name,
    dch.payment_day,
    dch.payment_count,
    ROUND(dch.daily_amount, 2) AS daily_amount,
    ROUND(dch.prev30_avg_amount, 2) AS prev30_avg_amount,
    ROUND(dch.daily_amount - dch.prev30_avg_amount, 2) AS amount_deviation,
    dch.distinct_staff_count,
    dch.distinct_store_count,
    dlp.last_payment_id,
    dlp.last_payment_ts,
    dlp.last_staff_id,
    stf.o02 || ' ' || stf.o03 AS last_staff_name,
    dlp.last_store_id,
    sto.j01 AS last_store_id_confirmed,
    COALESCE(lr.rental_count, 0) AS related_rentals_count,
    CASE
        WHEN COALESCE(lr.rental_count, 0) = 0 THEN 0.0
        ELSE ROUND(COALESCE(lr.late_return_count, 0) * 1.0 / lr.rental_count, 4)
    END AS late_return_share,
    cdr.country_day_amount_rank
FROM customer_daily_history AS dch
JOIN customer_geo AS cg
  ON cg.customer_id = dch.customer_id
LEFT JOIN daily_last_payment_one AS dlp
  ON dlp.customer_id = dch.customer_id
 AND dlp.payment_day = dch.payment_day
LEFT JOIN stf AS stf
  ON stf.o01 = dlp.last_staff_id
LEFT JOIN sto AS sto
  ON sto.j01 = dlp.last_store_id
LEFT JOIN late_rentals AS lr
  ON lr.customer_id = dch.customer_id
JOIN country_day_rank AS cdr
  ON cdr.customer_id = dch.customer_id
 AND cdr.payment_day = dch.payment_day
WHERE dch.prev30_days_count >= 5
  AND dch.prev30_avg_amount > 0
  AND (
      dch.daily_amount > 3.0 * dch.prev30_avg_amount
      OR dch.payment_count >= 5
  )
ORDER BY
    cdr.country_day_amount_rank,
    dch.daily_amount DESC,
    dch.payment_count DESC,
    dch.customer_id,
    dch.payment_day;