WITH daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        GROUP_CONCAT(DISTINCT p.p03) AS staff_ids
    FROM pay AS p
    JOIN stf AS s
        ON s.o01 = p.p03
    GROUP BY
        p.p02,
        date(p.p06)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        cn.c02 AS country,
        ct.d02 AS city
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ct
        ON ct.d01 = a.e05
    JOIN cnt AS cn
        ON cn.c01 = ct.d03
),
daily_with_personal_avg AS (
    SELECT
        dp.*,
        (
            SELECT AVG(dp_prev.day_amount)
            FROM daily_payments AS dp_prev
            WHERE dp_prev.customer_id = dp.customer_id
              AND dp_prev.payment_date >= date(dp.payment_date, '-30 days')
              AND dp_prev.payment_date < dp.payment_date
        ) AS personal_avg_prev_30d
    FROM daily_payments AS dp
),
country_daily_distribution AS (
    SELECT
        dwp.customer_id,
        dwp.payment_date,
        dwp.day_amount,
        cg.country,
        (
            SELECT COUNT(*)
            FROM daily_with_personal_avg AS x
            WHERE x.payment_date = dwp.payment_date
              AND x.personal_avg_prev_30d IS NOT NULL
              AND x.day_amount <= dwp.day_amount
              AND EXISTS (
                  SELECT 1
                  FROM customer_geo AS g
                  WHERE g.customer_id = x.customer_id
                    AND g.country = cg.country
              )
        ) AS leq_rank_in_country_day
    FROM daily_with_personal_avg AS dwp
    JOIN customer_geo AS cg
        ON cg.customer_id = dwp.customer_id
    WHERE dwp.personal_avg_prev_30d IS NOT NULL
),
country_day_p95 AS (
    -- Approximation of 95th percentile by taking "max(day_amount) for top 5% positions" using window functions
    SELECT DISTINCT
        cg.country,
        FIRST_VALUE(cd.day_amount) OVER (
            PARTITION BY cg.country
            ORDER BY cd.day_amount DESC
            ROWS BETWEEN 0 AND 0
        ) AS dummy
    FROM customer_geo cg
    JOIN daily_payments cd
        ON cd.customer_id = cg.customer_id
    LIMIT 0
),
country_p95_by_amount AS (
    SELECT
        cg.country,
        dpw.day_amount,
        dpw.payment_date,
        COUNT(*) OVER (PARTITION BY cg.country) AS country_rows,
        ROW_NUMBER() OVER (
            PARTITION BY cg.country
            ORDER BY dpw.day_amount DESC
        ) AS rn_desc
    FROM daily_with_personal_avg dpw
    JOIN customer_geo cg
        ON cg.customer_id = dpw.customer_id
    WHERE dpw.personal_avg_prev_30d IS NOT NULL
),
p95_threshold AS (
    SELECT
        country,
        MAX(day_amount) AS country_p95_daily_amount
    FROM country_p95_by_amount
    WHERE rn_desc <= CAST((0.05 * country_rows) + 0.999999 AS INT)
    GROUP BY country
),
suspicious_days AS (
    SELECT
        dwp.customer_id,
        dwp.payment_date,
        dwp.day_amount,
        dwp.payment_count,
        dwp.staff_count,
        dwp.store_count,
        dwp.staff_ids,
        dwp.personal_avg_prev_30d,
        pt.country_p95_daily_amount,
        (dwp.day_amount - dwp.personal_avg_prev_30d) AS deviation_from_personal_avg,
        cg.country,
        cg.city
    FROM daily_with_personal_avg dwp
    JOIN customer_geo cg
        ON cg.customer_id = dwp.customer_id
    JOIN p95_threshold pt
        ON pt.country = cg.country
    WHERE dwp.personal_avg_prev_30d IS NOT NULL
      AND dwp.payment_count >= 3
      AND dwp.staff_count >= 2
      AND dwp.store_count >= 2
      AND dwp.day_amount > 2.0 * dwp.personal_avg_prev_30d
      AND dwp.day_amount >= pt.country_p95_daily_amount
)
SELECT
    sd.customer_id,
    sd.country,
    sd.city,
    sd.payment_date,
    sd.payment_count,
    ROUND(sd.day_amount, 2) AS day_amount,
    sd.staff_ids AS staff_ids,
    ROUND(sd.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
    RANK() OVER (
        PARTITION BY sd.country, sd.payment_date
        ORDER BY sd.day_amount DESC
    ) AS suspicious_rank_in_country
FROM suspicious_days sd
ORDER BY
    sd.country,
    sd.payment_date,
    sd.day_amount DESC,
    sd.customer_id;