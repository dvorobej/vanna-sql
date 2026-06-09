WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        c.h02 AS home_store_id,
        ct.c01 AS country_id,
        ct.c02 AS country_name,
        cty.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS cty ON cty.d01 = a.e05
    JOIN cnt AS ct ON ct.c01 = cty.d03
),
payments_by_month AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06, 'start of month') AS month_start,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS month_amount,
        MAX(p.p05) AS max_payment,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        SUM(CASE WHEN inv.n03 <> (c.h02) THEN 1 ELSE 0 END) AS non_home_store_payment_count
    FROM pay AS p
    JOIN cus AS c ON c.h01 = p.p02
    JOIN ren AS r ON r.q01 = p.p04
    JOIN inv ON inv.n01 = r.q03
    WHERE p.p04 IS NOT NULL
    GROUP BY
        p.p02,
        date(p.p06, 'start of month')
),
staff_n_category_flags AS (
    SELECT
        pbm.*,
        (
            SELECT COUNT(DISTINCT cat.g01)
            FROM pay AS p2
            JOIN ren AS r2 ON r2.q01 = p2.p04
            JOIN inv AS inv2 ON inv2.n01 = r2.q03
            JOIN flc AS fc2 ON fc2.l01 = inv2.n02
            JOIN cat AS cat ON cat.g01 = fc2.l02
            WHERE p2.p02 = pbm.customer_id
              AND date(p2.p06, 'start of month') = pbm.month_start
        ) AS distinct_category_count
    FROM payments_by_month AS pbm
),
with_prev_avg3 AS (
    SELECT
        sncf.*,
        AVG(sncf.month_amount) OVER (
            PARTITION BY sncf.customer_id
            ORDER BY sncf.month_start
            ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
        ) AS prev_3_months_avg_amount
    FROM staff_n_category_flags AS sncf
),
country_month_rank AS (
    SELECT
        wpa3.*,
        cg.country_id,
        cg.city_name,
        RANK() OVER (
            PARTITION BY cg.country_id, wpa3.month_start
            ORDER BY wpa3.month_amount DESC
        ) AS customer_country_month_rank
    FROM with_prev_avg3 AS wpa3
    JOIN customer_geo AS cg ON cg.customer_id = wpa3.customer_id
)
SELECT
    cmr.month_start AS month,
    cmr.country_id AS country_id,
    cg.country_name AS country_name,
    cmr.city_name AS city,
    ROUND(cmr.month_amount, 2) AS payment_sum,
    cmr.payment_count AS payment_count,
    ROUND(cmr.max_payment, 2) AS max_payment,
    ROUND(1.0 * cmr.non_home_store_payment_count / NULLIF(cmr.payment_count, 0), 4) AS non_home_store_payment_share,
    cmr.customer_country_month_rank AS country_month_amount_rank
FROM country_month_rank AS cmr
JOIN customer_geo AS cg
    ON cg.customer_id = cmr.customer_id
WHERE
    cmr.prev_3_months_avg_amount IS NOT NULL
    AND cmr.prev_3_months_avg_amount > 0
    AND cmr.month_amount > 3.0 * cmr.prev_3_months_avg_amount
    AND cmr.distinct_staff_count >= 2
    AND cmr.distinct_category_count >= 3
ORDER BY
    cmr.month_start,
    cmr.country_id,
    cmr.customer_country_month_rank,
    cmr.customer_id;