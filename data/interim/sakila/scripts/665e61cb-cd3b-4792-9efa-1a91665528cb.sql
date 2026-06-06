WITH payment_enriched AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        date(p.p06, 'start of month') AS month_start,
        CAST(strftime('%Y', p.p06) AS INTEGER) * 12 + CAST(strftime('%m', p.p06) AS INTEGER) AS month_index,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        p.p03 AS staff_id,
        COALESCE(inv.n03, stf.o07) AS store_id,
        CAST(p.p05 AS REAL) AS payment_amount,
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM ren r2
                JOIN inv i2 ON i2.n01 = r2.q03
                JOIN flc fc ON fc.l01 = i2.n02
                JOIN cat ca ON ca.g01 = fc.l02
                WHERE r2.q01 = p.p04
                  AND ca.g02 IN ('Action', 'New')
            )
            THEN 1
            ELSE 0
        END AS is_action_or_new
    FROM pay p
    JOIN cus c ON c.h01 = p.p02
    JOIN adr a ON a.e01 = c.h06
    JOIN cty city ON city.d01 = a.e05
    JOIN cnt ON cnt.c01 = city.d03
    JOIN stf ON stf.o01 = p.p03
    LEFT JOIN ren r ON r.q01 = p.p04
    LEFT JOIN inv ON inv.n01 = r.q03
),
customer_month_stats AS (
    SELECT
        customer_id,
        customer_name,
        month_start,
        month_index,
        country_id,
        country_name,
        SUM(payment_amount) AS monthly_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT staff_id) AS distinct_staff_count,
        COUNT(DISTINCT store_id) AS distinct_store_count,
        SUM(is_action_or_new) * 1.0 / COUNT(*) AS action_or_new_payment_share
    FROM payment_enriched
    GROUP BY
        customer_id,
        customer_name,
        month_start,
        month_index,
        country_id,
        country_name
),
customer_month_with_history AS (
    SELECT
        cms.*,
        (
            SELECT AVG(prev.monthly_amount)
            FROM customer_month_stats prev
            WHERE prev.customer_id = cms.customer_id
              AND prev.month_index BETWEEN cms.month_index - 3 AND cms.month_index - 1
        ) AS prev3_avg_monthly_amount,
        (
            SELECT COUNT(*)
            FROM customer_month_stats prev
            WHERE prev.customer_id = cms.customer_id
              AND prev.month_index BETWEEN cms.month_index - 3 AND cms.month_index - 1
        ) AS prev3_month_count
    FROM customer_month_stats cms
),
ranked_country_month AS (
    SELECT
        cmh.*,
        ROW_NUMBER() OVER (
            PARTITION BY cmh.country_id, cmh.month_start
            ORDER BY cmh.monthly_amount
        ) AS ascending_amount_rn,
        COUNT(*) OVER (
            PARTITION BY cmh.country_id, cmh.month_start
        ) AS country_customer_count,
        RANK() OVER (
            PARTITION BY cmh.country_id, cmh.month_start
            ORDER BY cmh.monthly_amount DESC
        ) AS country_month_rank
    FROM customer_month_with_history cmh
),
percentile_positions AS (
    SELECT
        rcm.*,
        CAST((95 * country_customer_count + 5) / 100 AS INTEGER) AS p95_lower_rn,
        CAST((95 * country_customer_count + 5 + 99) / 100 AS INTEGER) AS p95_upper_rn,
        ((95 * country_customer_count + 5) % 100) / 100.0 AS p95_fraction
    FROM ranked_country_month rcm
),
country_month_p95 AS (
    SELECT
        month_start,
        country_id,
        MAX(CASE WHEN ascending_amount_rn = p95_lower_rn THEN monthly_amount END)
        +
        (
            MAX(CASE WHEN ascending_amount_rn = p95_upper_rn THEN monthly_amount END)
            -
            MAX(CASE WHEN ascending_amount_rn = p95_lower_rn THEN monthly_amount END)
        ) * MAX(p95_fraction) AS country_p95_monthly_amount
    FROM percentile_positions
    GROUP BY
        month_start,
        country_id
)
SELECT
    pp.month_start,
    pp.country_name,
    pp.customer_id,
    pp.customer_name,
    ROUND(pp.monthly_amount, 2) AS monthly_amount,
    ROUND(pp.prev3_avg_monthly_amount, 2) AS prev3_avg_monthly_amount,
    ROUND(pp.monthly_amount / pp.prev3_avg_monthly_amount, 2) AS amount_to_prev3_avg_ratio,
    ROUND(p95.country_p95_monthly_amount, 2) AS country_p95_monthly_amount,
    pp.payment_count,
    pp.distinct_staff_count,
    pp.distinct_store_count,
    ROUND(pp.action_or_new_payment_share, 4) AS action_or_new_payment_share,
    pp.country_month_rank
FROM percentile_positions pp
JOIN country_month_p95 p95
  ON p95.month_start = pp.month_start
 AND p95.country_id = pp.country_id
WHERE pp.prev3_month_count = 3
  AND pp.prev3_avg_monthly_amount > 0
  AND pp.monthly_amount >= 2 * pp.prev3_avg_monthly_amount
  AND pp.monthly_amount > p95.country_p95_monthly_amount
ORDER BY
    pp.month_start,
    pp.country_name,
    pp.country_month_rank,
    pp.monthly_amount DESC;