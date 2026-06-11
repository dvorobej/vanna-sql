WITH payment_details AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        p.p04 AS rental_id,
        CAST(p.p05 AS REAL) AS amount,
        date(p.p06) AS payment_date,
        date(p.p06) AS day_key,
        stf.o02 AS staff_first_name,
        stf.o03 AS staff_last_name,
        stf.o07 AS store_id
    FROM pay AS p
    JOIN stf AS stf
        ON stf.o01 = p.p03
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS country_name,
        cty.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty
        ON cty.d01 = a.e05
    JOIN cnt
        ON cnt.c01 = cty.d03
),
daily_rollup AS (
    SELECT
        pd.customer_id,
        cg.customer_name,
        cg.country_name,
        cg.city_name,
        pd.day_key AS payment_date,
        COUNT(pd.payment_id) AS payment_count,
        SUM(pd.amount) AS day_amount,
        COUNT(DISTINCT pd.staff_id) AS staff_count,
        COUNT(DISTINCT pd.store_id) AS store_count,
        MAX(pd.amount) AS max_payment,
        MIN(pd.payment_id) AS min_payment_id,
        MAX(pd.payment_id) AS max_payment_id
    FROM payment_details AS pd
    JOIN customer_geo AS cg
        ON cg.customer_id = pd.customer_id
    GROUP BY
        pd.customer_id,
        cg.customer_name,
        cg.country_name,
        cg.city_name,
        pd.day_key
),
staff_store_lists AS (
    SELECT
        pd.customer_id,
        pd.day_key AS payment_date,
        group_concat(DISTINCT (pd.staff_first_name || ' ' || pd.staff_last_name)) AS staff_list,
        group_concat(DISTINCT pd.store_id) AS store_list
    FROM payment_details AS pd
    GROUP BY
        pd.customer_id,
        pd.day_key
),
daily_with_baselines AS (
    SELECT
        dr.*,
        (
            SELECT AVG(dr_prev.day_amount)
            FROM daily_rollup AS dr_prev
            WHERE dr_prev.customer_id = dr.customer_id
              AND dr_prev.payment_date >= date(dr.payment_date, '-30 day')
              AND dr_prev.payment_date < dr.payment_date
        ) AS customer_avg_prev_30d
    FROM daily_rollup AS dr
),
country_daily_ranked AS (
    SELECT
        dr.country_name,
        dr.payment_date,
        dr.day_amount,
        ROW_NUMBER() OVER (
            PARTITION BY dr.country_name
            ORDER BY dr.day_amount
        ) AS rn,
        COUNT(*) OVER (PARTITION BY dr.country_name) AS cnt_days
    FROM daily_with_baselines AS dr
),
country_p95 AS (
    SELECT
        country_name,
        MIN(day_amount) AS p95_day_amount
    FROM (
        SELECT
            country_name,
            day_amount,
            rn,
            cnt_days
        FROM country_daily_ranked
        WHERE rn >= ((95 * cnt_days + 99) / 100)
    ) AS x
    GROUP BY country_name
),
final_scored AS (
    SELECT
        dwr.*,
        c95.p95_day_amount,
        (dwr.day_amount / NULLIF(dwr.customer_avg_prev_30d, 0)) AS ratio_vs_customer_avg,
        (dwr.day_amount / NULLIF(c95.p95_day_amount, 0)) AS ratio_vs_country_p95
    FROM daily_with_baselines AS dwr
    JOIN country_p95 AS c95
        ON c95.country_name = dwr.country_name
)
SELECT
    fs.customer_name,
    fs.city_name,
    fs.country_name,
    fs.payment_date AS suspicious_date,
    ROUND(fs.day_amount, 2) AS day_amount,
    fs.payment_count,
    ssl.staff_list,
    fs.staff_count,
    ssl.store_list,
    fs.store_count,
    (SELECT MIN(p2.p06) FROM pay AS p2 WHERE p2.p02 = fs.customer_id) AS first_operation_time,
    (SELECT MAX(p2.p06) FROM pay AS p2 WHERE p2.p02 = fs.customer_id) AS last_operation_time,
    ROUND(fs.max_payment, 2) AS max_payment,
    RANK() OVER (
        PARTITION BY fs.country_name
        ORDER BY (fs.day_amount - fs.p95_day_amount) DESC,
                 fs.day_amount DESC
    ) AS suspicion_rank
FROM final_scored AS fs
JOIN staff_store_lists AS ssl
    ON ssl.customer_id = fs.customer_id
   AND ssl.payment_date = fs.payment_date
WHERE fs.payment_count >= 3
  AND fs.staff_count >= 2
  AND fs.store_count >= 1
  AND fs.customer_avg_prev_30d IS NOT NULL
  AND fs.customer_avg_prev_30d > 0
  AND fs.day_amount > fs.customer_avg_prev_30d
  AND fs.day_amount > fs.p95_day_amount
ORDER BY
    fs.country_name,
    suspicion_rank,
    fs.day_amount DESC,
    fs.customer_name;