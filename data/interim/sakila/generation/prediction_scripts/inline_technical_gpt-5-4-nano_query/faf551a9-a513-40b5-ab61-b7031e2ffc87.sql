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
daily_customer_pay AS (
    SELECT
        p.p02 AS customer_id,
        cg.first_name,
        cg.last_name,
        cg.country_name,
        cg.city_name,
        date(p.p06) AS payment_day,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(*) AS payment_count,
        MAX(CAST(p.p05 AS REAL)) AS max_payment,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN customer_geo AS cg ON cg.customer_id = p.p02
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY
        p.p02,
        cg.first_name,
        cg.last_name,
        cg.country_name,
        cg.city_name,
        date(p.p06)
),
customer_prev_30 AS (
    SELECT
        dcp.*,
        (
            SELECT AVG(CAST(dp2.day_amount AS REAL))
            FROM daily_customer_pay AS dp2
            WHERE dp2.customer_id = dcp.customer_id
              AND dp2.payment_day >= date(dcp.payment_day, '-30 day')
              AND dp2.payment_day < dcp.payment_day
        ) AS personal_avg_daily_prev_30
    FROM daily_customer_pay AS dcp
),
country_daily_ranked AS (
    SELECT
        dcp.*,
        PERCENT_RANK() OVER (
            PARTITION BY dcp.country_name
            ORDER BY dcp.day_amount
        ) AS pr
    FROM daily_customer_pay AS dcp
),
country_p95 AS (
    SELECT
        country_name,
        MAX(day_amount) AS p95_day_amount
    FROM (
        SELECT
            country_name,
            day_amount,
            NTILE(100) OVER (
                PARTITION BY country_name
                ORDER BY day_amount
            ) AS tile100
        FROM daily_customer_pay
    ) x
    WHERE tile100 >= 96
    GROUP BY country_name
),
flagged_days AS (
    SELECT
        c30.*,
        cp95.p95_day_amount,
        (c30.day_amount - c30.personal_avg_daily_prev_30) AS deviation_from_personal_avg,
        (c30.day_amount / NULLIF(c30.personal_avg_daily_prev_30, 0)) AS spike_ratio
    FROM customer_prev_30 AS c30
    JOIN country_p95 AS cp95
      ON cp95.country_name = c30.country_name
    WHERE c30.personal_avg_daily_prev_30 IS NOT NULL
      AND c30.personal_avg_daily_prev_30 > 0
      AND c30.day_amount >= 3.0 * c30.personal_avg_daily_prev_30
      AND c30.day_amount > cp95.p95_day_amount
),
day_store_level AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_day,
        GROUP_CONCAT(DISTINCT s.o07) AS store_list
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY p.p02, date(p.p06)
),
ranked AS (
    SELECT
        fd.*,
        RANK() OVER (
            PARTITION BY fd.country_name
            ORDER BY fd.day_amount DESC
        ) AS suspicion_rank_in_country
    FROM flagged_days AS fd
)
SELECT
    r.payment_day AS spike_date,
    r.first_name,
    r.last_name,
    r.country_name,
    r.city_name,
    dsl.store_list AS store,
    r.payment_count AS payment_count,
    ROUND(r.day_amount, 2) AS day_amount,
    ROUND(r.personal_avg_daily_prev_30, 2) AS avg_daily_prev_30,
    ROUND(r.deviation_from_personal_avg, 2) AS deviation_from_avg,
    r.suspicion_rank_in_country
FROM ranked AS r
LEFT JOIN day_store_level AS dsl
  ON dsl.customer_id = r.customer_id
 AND dsl.payment_day = r.payment_day
ORDER BY
    r.country_name,
    r.suspicion_rank_in_country,
    r.payment_day,
    r.customer_id;