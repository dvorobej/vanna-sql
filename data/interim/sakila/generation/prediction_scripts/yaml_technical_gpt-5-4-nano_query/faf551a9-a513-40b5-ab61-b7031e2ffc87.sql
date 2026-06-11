WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        cn.c02 AS country_name,
        ci.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS cn ON cn.c01 = ci.d03
),
daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        p.p03 AS staff_id,
        COALESCE(sto.j01, NULL) AS store_id,
        cg.first_name,
        cg.last_name,
        cg.country_name,
        cg.city_name,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(*) AS payment_count
    FROM pay AS p
    JOIN customer_geo AS cg ON cg.customer_id = p.p02
    LEFT JOIN ren r ON r.q01 = p.p04
    LEFT JOIN inv i ON i.n01 = r.q03
    LEFT JOIN sto ON sto.j01 = COALESCE(i.n03, sto.j01)
    GROUP BY
        p.p02,
        date(p.p06),
        p.p03,
        COALESCE(sto.j01, NULL),
        cg.first_name,
        cg.last_name,
        cg.country_name,
        cg.city_name
),
daily_by_customer_day AS (
    SELECT
        customer_id,
        first_name,
        last_name,
        country_name,
        city_name,
        payment_date,
        SUM(day_amount) AS day_amount,
        SUM(payment_count) AS payment_count,
        COUNT(DISTINCT staff_id) AS distinct_staff_count,
        GROUP_CONCAT(DISTINCT CAST(store_id AS TEXT)) AS store_ids_list,
        SUM(CASE WHEN store_id IS NOT NULL THEN 1 ELSE 0 END) AS store_present_payments
    FROM daily_payments
    GROUP BY
        customer_id,
        first_name,
        last_name,
        country_name,
        city_name,
        payment_date
),
with_personal_avg AS (
    SELECT
        d.*,
        (
            SELECT AVG(d2.day_amount)
            FROM daily_by_customer_day d2
            WHERE d2.customer_id = d.customer_id
              AND d2.payment_date >= date(d.payment_date, '-30 day')
              AND d2.payment_date < d.payment_date
        ) AS avg_daily_prev_30d
    FROM daily_by_customer_day d
),
country_p95 AS (
    SELECT
        dp.country_name,
        dp.payment_date,
        dp.day_amount,
        -- Compute percentile threshold per country based on all daily sums
        PERCENT_RANK() OVER (PARTITION BY dp.country_name ORDER BY dp.day_amount) AS pr
    FROM daily_by_customer_day dp
),
country_p95_threshold AS (
    SELECT
        country_name,
        MAX(day_amount) AS p95_day_amount
    FROM (
        SELECT
            country_name,
            day_amount,
            ROW_NUMBER() OVER (PARTITION BY country_name ORDER BY day_amount) AS rn,
            COUNT(*) OVER (PARTITION BY country_name) AS cnt_all
        FROM daily_by_customer_day
    ) x
    WHERE rn >= CAST(0.95 * cnt_all AS INTEGER)
    GROUP BY country_name
),
flagged AS (
    SELECT
        w.customer_id,
        w.first_name,
        w.last_name,
        w.country_name,
        w.city_name,
        w.payment_date,
        w.payment_count,
        w.day_amount,
        w.avg_daily_prev_30d,
        (w.day_amount - w.avg_daily_prev_30d) AS deviation_from_avg,
        (w.day_amount / w.avg_daily_prev_30d) AS surge_ratio,
        cpt.p95_day_amount
    FROM with_personal_avg w
    JOIN country_p95_threshold cpt
      ON cpt.country_name = w.country_name
    WHERE w.avg_daily_prev_30d IS NOT NULL
      AND w.avg_daily_prev_30d > 0
      AND w.day_amount >= 3.0 * w.avg_daily_prev_30d
      AND w.day_amount > cpt.p95_day_amount
),
ranked AS (
    SELECT
        f.*,
        RANK() OVER (
            PARTITION BY f.country_name
            ORDER BY f.surge_ratio DESC, f.day_amount DESC, f.customer_id, f.payment_date
        ) AS customer_surge_rank_in_country
    FROM flagged f
)
SELECT
    r.payment_date AS surge_date,
    r.first_name,
    r.last_name,
    r.country_name AS country,
    r.city_name,
    NULL AS store_id,
    r.payment_count,
    ROUND(r.day_amount, 2) AS day_amount,
    ROUND(r.avg_daily_prev_30d, 2) AS avg_daily_prev_30d,
    ROUND(r.deviation_from_avg, 2) AS deviation_from_avg,
    r.customer_surge_rank_in_country
FROM ranked r
ORDER BY
    r.country_name,
    r.customer_surge_rank_in_country,
    r.payment_date,
    r.customer_id;