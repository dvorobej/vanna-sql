WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c01 AS country_id,
        cnt.c02 AS country,
        cty.d02 AS city,
        c.h06 AS address_id
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS cty ON cty.d01 = a.e05
    JOIN cnt AS cnt ON cnt.c01 = cty.d03
),
daily_by_customer AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_sum,
        GROUP_CONCAT(DISTINCT CAST(p.p03 AS TEXT)) AS staff_ids,
        GROUP_CONCAT(DISTINCT CAST(s.o07 AS TEXT)) AS store_ids,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, date(p.p06)
),
daily_with_personal_avg AS (
    SELECT
        d.*,
        (
            SELECT AVG(CAST(p2.p05 AS REAL))
            FROM pay AS p2
            WHERE p2.p02 = d.customer_id
              AND date(p2.p06) >= date(d.payment_date, '-30 days')
              AND date(p2.p06) < d.payment_date
        ) AS personal_avg_prev_30d
    FROM daily_by_customer AS d
),
country_daily_sums AS (
    SELECT
        cg.country_id,
        d.payment_date,
        d.customer_id,
        d.day_sum
    FROM daily_with_personal_avg AS d
    JOIN customer_geo AS cg ON cg.customer_id = d.customer_id
),
country_p95 AS (
    SELECT
        country_id,
        payment_date,
        day_sum,
        ROW_NUMBER() OVER (PARTITION BY country_id, payment_date ORDER BY day_sum) AS rn,
        COUNT(*) OVER (PARTITION BY country_id, payment_date) AS cnt
    FROM country_daily_sums
),
country_p95_threshold AS (
    SELECT
        country_id,
        payment_date,
        MAX(day_sum) AS p95_day_sum
    FROM country_p95
    WHERE rn >= CAST((0.95 * cnt) + 0.999 AS INTEGER)
    GROUP BY country_id, payment_date
),
qualified AS (
    SELECT
        d.payment_date,
        d.customer_id,
        cg.country_id,
        cg.country,
        cg.city,
        d.payment_count,
        d.day_sum,
        d.staff_ids,
        d.store_ids,
        d.staff_count,
        d.store_count,
        d.personal_avg_prev_30d,
        (d.day_sum - d.personal_avg_prev_30d) AS deviation_from_personal_avg,
        cpt.p95_day_sum
    FROM daily_with_personal_avg d
    JOIN customer_geo cg ON cg.customer_id = d.customer_id
    JOIN country_p95_threshold cpt
      ON cpt.country_id = cg.country_id
     AND cpt.payment_date = d.payment_date
    WHERE d.payment_count >= 3
      AND d.staff_count >= 2 OR d.store_count >= 2
      AND d.personal_avg_prev_30d IS NOT NULL
      AND d.personal_avg_prev_30d > 0
      AND d.day_sum > 2.0 * d.personal_avg_prev_30d
      AND d.day_sum > cpt.p95_day_sum
),
ranked AS (
    SELECT
        q.*,
        DENSE_RANK() OVER (
            PARTITION BY q.country_id
            ORDER BY q.deviation_from_personal_avg DESC
        ) AS suspicion_rank_in_country
    FROM qualified q
)
SELECT
    customer_id,
    country,
    city,
    payment_date AS spike_date,
    payment_count,
    ROUND(day_sum, 2) AS day_sum,
    staff_ids AS staff_list,
    ROUND(deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
    suspicion_rank_in_country
FROM ranked
ORDER BY
    country,
    suspicion_rank_in_country,
    spike_date,
    customer_id;