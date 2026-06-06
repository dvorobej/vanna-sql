WITH payment_base AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_day,
        CAST(p.p05 AS REAL) AS amount,
        p.p03 AS staff_id,
        stf.o07 AS store_id,
        p.p04 AS rental_id
    FROM pay AS p
    JOIN stf
        ON stf.o01 = p.p03
),
customer_geo AS (
    SELECT
        cus.h01 AS customer_id,
        cus.h03 || ' ' || cus.h04 AS customer_name,
        cty.d02 AS city,
        cnt.c01 AS country_id,
        cnt.c02 AS country
    FROM cus
    JOIN adr
        ON adr.e01 = cus.h06
    JOIN cty
        ON cty.d01 = adr.e05
    JOIN cnt
        ON cnt.c01 = cty.d03
),
daily_customer AS (
    SELECT
        pb.customer_id,
        cg.customer_name,
        cg.city,
        cg.country_id,
        cg.country,
        pb.payment_day,
        SUM(pb.amount) AS daily_payment_amount,
        COUNT(*) AS daily_payment_count,
        COUNT(DISTINCT pb.staff_id) AS staff_count,
        GROUP_CONCAT(DISTINCT pb.staff_id) AS staff_ids,
        COUNT(DISTINCT pb.store_id) AS store_count,
        GROUP_CONCAT(DISTINCT pb.store_id) AS store_ids,
        COUNT(DISTINCT pb.rental_id) AS linked_rental_count
    FROM payment_base AS pb
    JOIN customer_geo AS cg
        ON cg.customer_id = pb.customer_id
    GROUP BY
        pb.customer_id,
        cg.customer_name,
        cg.city,
        cg.country_id,
        cg.country,
        pb.payment_day
),
daily_with_history AS (
    SELECT
        dc.*,
        COALESCE((
            SELECT SUM(prev.daily_payment_amount) / 30.0
            FROM daily_customer AS prev
            WHERE prev.customer_id = dc.customer_id
              AND prev.payment_day >= DATE(dc.payment_day, '-30 day')
              AND prev.payment_day < dc.payment_day
        ), 0.0) AS avg_30d_daily_amount,
        COALESCE((
            SELECT SUM(prev.daily_payment_count) / 30.0
            FROM daily_customer AS prev
            WHERE prev.customer_id = dc.customer_id
              AND prev.payment_day >= DATE(dc.payment_day, '-30 day')
              AND prev.payment_day < dc.payment_day
        ), 0.0) AS avg_30d_daily_count
    FROM daily_customer AS dc
),
ranked_country_days AS (
    SELECT
        dwh.*,
        RANK() OVER (
            PARTITION BY dwh.country_id, dwh.payment_day
            ORDER BY dwh.daily_payment_amount DESC
        ) AS country_daily_amount_rank,
        RANK() OVER (
            PARTITION BY dwh.country_id, dwh.payment_day
            ORDER BY dwh.daily_payment_count DESC
        ) AS country_daily_count_rank,
        COUNT(*) OVER (
            PARTITION BY dwh.country_id, dwh.payment_day
        ) AS country_daily_customer_count
    FROM daily_with_history AS dwh
),
suspicious_days AS (
    SELECT
        *,
        daily_payment_amount / NULLIF(avg_30d_daily_amount, 0) AS amount_to_30d_avg_ratio,
        daily_payment_count / NULLIF(avg_30d_daily_count, 0) AS count_to_30d_avg_ratio,
        CASE
            WHEN staff_count > 1 OR store_count > 1 THEN 1
            ELSE 0
        END AS multiple_staff_or_store_flag
    FROM ranked_country_days
    WHERE avg_30d_daily_amount > 0
      AND avg_30d_daily_count > 0
      AND daily_payment_amount >= avg_30d_daily_amount * 3.0
      AND daily_payment_count >= avg_30d_daily_count * 3.0
      AND country_daily_amount_rank <= (country_daily_customer_count + 19) / 20
      AND country_daily_count_rank <= (country_daily_customer_count + 19) / 20
)
SELECT
    customer_id,
    customer_name,
    city,
    country,
    payment_day,
    ROUND(daily_payment_amount, 2) AS daily_payment_amount,
    daily_payment_count,
    ROUND(avg_30d_daily_amount, 2) AS avg_30d_daily_amount,
    ROUND(avg_30d_daily_count, 2) AS avg_30d_daily_count,
    ROUND(amount_to_30d_avg_ratio, 2) AS amount_to_30d_avg_ratio,
    ROUND(count_to_30d_avg_ratio, 2) AS count_to_30d_avg_ratio,
    store_count,
    store_ids,
    staff_count,
    staff_ids,
    linked_rental_count,
    country_daily_amount_rank,
    multiple_staff_or_store_flag
FROM suspicious_days
ORDER BY
    payment_day,
    country,
    country_daily_amount_rank,
    daily_payment_amount DESC,
    customer_id;