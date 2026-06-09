WITH payment_base AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        p.p05 AS amount,
        p.p06 AS payment_ts,
        date(p.p06, 'start of month') AS month_start,
        cu.h02 AS home_store_id,
        ctry.c01 AS country_id,
        ctry.c02 AS country_name,
        city.d02 AS city_name,
        fcc.g01 AS category_id
    FROM pay AS p
    JOIN cus AS cu
        ON cu.h01 = p.p02
    JOIN ren AS r
        ON r.q01 = p.p04
    JOIN inv AS inv
        ON inv.n01 = r.q03
    JOIN flc AS fcc
        ON fcc.l01 = inv.n02
    JOIN adr AS a
        ON a.e01 = cu.h06
    JOIN cty AS city
        ON city.d01 = a.e05
    JOIN cnt AS ctry
        ON ctry.c01 = city.d03
    WHERE p.p04 IS NOT NULL
),
monthly_customer AS (
    SELECT
        customer_id,
        month_start,
        country_id,
        country_name,
        city_name,
        SUM(amount) AS month_total_amount,
        COUNT(payment_id) AS payment_count,
        MAX(amount) AS max_payment,
        COUNT(DISTINCT staff_id) AS distinct_staff_count,
        COUNT(DISTINCT CASE WHEN home_store_id IS NULL THEN NULL WHEN home_store_id <> (SELECT i.n03 FROM inv i WHERE i.n01 = (SELECT r2.q03 FROM ren r2 WHERE r2.q01 = p2.p04)) THEN 1 END) AS dummy
    FROM payment_base
    LEFT JOIN ren r
        ON r.q01 IS NOT NULL
    GROUP BY
        customer_id,
        month_start,
        country_id,
        country_name,
        city_name
),
monthly_with_prev AS (
    SELECT
        mb.*,
        AVG(mb_prev.month_total_amount) AS prev_3_month_avg_amount
    FROM monthly_customer AS mb
    JOIN monthly_customer AS mb_prev
      ON mb_prev.customer_id = mb.customer_id
     AND mb_prev.month_start >= date(mb.month_start, '-3 months')
     AND mb_prev.month_start < mb.month_start
    GROUP BY
        mb.customer_id,
        mb.month_start,
        mb.country_id,
        mb.country_name,
        mb.city_name,
        mb.month_total_amount,
        mb.payment_count,
        mb.max_payment,
        mb.distinct_staff_count
),
monthly_categories AS (
    SELECT
        customer_id,
        month_start,
        COUNT(DISTINCT category_id) AS distinct_category_count
    FROM payment_base
    GROUP BY
        customer_id,
        month_start
),
monthly_foreign_share AS (
    SELECT
        customer_id,
        month_start,
        1.0 * SUM(
            CASE
                WHEN home_store_id <> issuing_store_id THEN 1
                ELSE 0
            END
        ) / COUNT(*) AS foreign_store_payment_share
    FROM (
        SELECT
            pb.*,
            (SELECT i2.n03 FROM inv i2 WHERE i2.n01 = (SELECT r3.q03 FROM ren r3 WHERE r3.q01 = pb.payment_id)) AS issuing_store_id
        FROM payment_base pb
    ) x
    GROUP BY
        customer_id,
        month_start
),
qualifying_months AS (
    SELECT
        mwp.customer_id,
        mwp.month_start,
        mwp.country_id,
        mwp.country_name,
        mwp.city_name,
        mwp.month_total_amount,
        mwp.payment_count,
        mwp.max_payment,
        mwp.distinct_staff_count,
        mwp.prev_3_month_avg_amount,
        mc.distinct_category_count,
        mfs.foreign_store_payment_share
    FROM monthly_with_prev AS mwp
    JOIN monthly_categories AS mc
      ON mc.customer_id = mwp.customer_id
     AND mc.month_start = mwp.month_start
    JOIN monthly_foreign_share AS mfs
      ON mfs.customer_id = mwp.customer_id
     AND mfs.month_start = mwp.month_start
    WHERE mwp.prev_3_month_avg_amount IS NOT NULL
      AND mwp.prev_3_month_avg_amount > 0
      AND mwp.month_total_amount > 3 * mwp.prev_3_month_avg_amount
      AND mwp.distinct_staff_count >= 2
      AND mc.distinct_category_count >= 3
),
ranked_in_country AS (
    SELECT
        qm.*,
        RANK() OVER (
            PARTITION BY qm.country_id, qm.month_start
            ORDER BY qm.month_total_amount DESC
        ) AS country_month_payment_rank
    FROM qualifying_months qm
)
SELECT
    r.customer_id,
    r.month_start,
    r.country_name,
    r.city_name,
    ROUND(r.month_total_amount, 2) AS month_total_amount,
    r.payment_count,
    ROUND(r.max_payment, 2) AS max_payment,
    ROUND(r.foreign_store_payment_share, 4) AS foreign_store_payment_share,
    r.country_month_payment_rank
FROM ranked_in_country AS r
ORDER BY
    r.month_start,
    r.country_name,
    r.country_month_payment_rank,
    r.month_total_amount DESC;