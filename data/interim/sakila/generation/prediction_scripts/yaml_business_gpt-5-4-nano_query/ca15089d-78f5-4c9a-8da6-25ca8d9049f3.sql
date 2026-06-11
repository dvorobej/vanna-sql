WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        co.c02 AS country_name,
        ci.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
),
payments_base AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        DATE(p.p06) AS payment_day,
        p.p05 AS amount,
        p.p03 AS staff_id,
        s.o07 AS staff_store_id
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
),
monthly AS (
    SELECT
        pb.customer_id,
        pb.month_start,
        COUNT(*) AS payment_count,
        SUM(pb.amount) AS month_sum,
        MAX(pb.amount) AS max_payment,
        SUM(CASE WHEN pb.staff_store_id IS NOT NULL THEN 1 ELSE 0 END) AS staff_payments_count,
        COUNT(DISTINCT pb.staff_id) AS staff_count,
        COUNT(DISTINCT pb.staff_store_id) AS store_count
    FROM payments_base AS pb
    GROUP BY pb.customer_id, pb.month_start
),
monthly_prev_avg AS (
    SELECT
        m.*,
        AVG(m.month_sum) OVER (
            PARTITION BY m.customer_id
            ORDER BY m.month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_avg_month_sum
    FROM monthly AS m
),
monthly_days_staff_store AS (
    SELECT
        pb.customer_id,
        pb.month_start,
        COUNT(DISTINCT pb.payment_day) AS distinct_payment_days,
        COUNT(DISTINCT pb.staff_id) AS distinct_staff_in_month,
        COUNT(DISTINCT pb.staff_store_id) AS distinct_stores_in_month
    FROM payments_base AS pb
    GROUP BY pb.customer_id, pb.month_start
),
qualified AS (
    SELECT
        mp.customer_id,
        mp.month_start,
        mp.payment_count,
        mp.month_sum,
        mp.max_payment,
        mp.staff_count AS staff_count_in_month,
        mp.store_count AS store_count_in_month,
        mp.prev_avg_month_sum,
        mds.distinct_payment_days,
        mds.distinct_staff_in_month,
        mds.distinct_stores_in_month
    FROM monthly_prev_avg AS mp
    JOIN monthly_days_staff_store AS mds
      ON mds.customer_id = mp.customer_id
     AND mds.month_start = mp.month_start
    WHERE mp.prev_avg_month_sum IS NOT NULL
      AND mp.payment_count >= 3
      AND mp.month_sum >= 3.0 * mp.prev_avg_month_sum
      AND mds.distinct_payment_days >= 3
      AND (mds.distinct_staff_in_month >= 2 OR mds.distinct_stores_in_month >= 2)
),
ranked AS (
    SELECT
        q.*,
        cg.country_name,
        cg.city_name,
        cg.first_name,
        cg.last_name,
        RANK() OVER (
            PARTITION BY cg.country_name, q.month_start
            ORDER BY q.month_sum DESC
        ) AS country_month_amount_rank
    FROM qualified AS q
    JOIN customer_geo AS cg ON cg.customer_id = q.customer_id
)
SELECT
    month_start AS month,
    last_name || ' ' || first_name AS fio,
    country_name AS country,
    city_name AS city,
    payment_count,
    ROUND(month_sum, 2) AS total_amount,
    ROUND(max_payment, 2) AS max_payment,
    ROUND(max_payment / NULLIF(month_sum, 0), 4) AS max_payment_share,
    distinct_staff_in_month AS different_staff_count,
    distinct_stores_in_month AS different_stores_count,
    country_month_amount_rank AS country_month_rank
FROM ranked
ORDER BY
    country_name,
    month_start,
    country_month_amount_rank,
    month_sum DESC,
    fio;