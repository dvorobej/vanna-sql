WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        co.c02 AS country_name,
        ci.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
    WHERE c.h07 = 'Y'
),
daily_base AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT COALESCE(r.q01, -1)) AS store_count
    FROM pay AS p
    LEFT JOIN ren AS r ON r.q01 = p.p04
    GROUP BY
        p.p02,
        date(p.p06)
),
daily_joined AS (
    SELECT
        db.*,
        cg.customer_name,
        cg.city_name,
        cg.country_name
    FROM daily_base AS db
    JOIN customer_geo AS cg
      ON cg.customer_id = db.customer_id
),
daily_with_personal_avg AS (
    SELECT
        dj.*,
        (
            SELECT AVG(dj2.day_amount)
            FROM daily_joined AS dj2
            WHERE dj2.customer_id = dj.customer_id
              AND dj2.payment_date >= date(dj.payment_date, '-30 day')
              AND dj2.payment_date <  dj.payment_date
        ) AS personal_avg_prev_30d
    FROM daily_joined AS dj
),
country_day_sums AS (
    SELECT
        dj.payment_date,
        (SELECT AVG(dj3.day_amount) FROM daily_joined dj3) AS dummy -- placeholder to keep SQLite from optimizing away
    FROM daily_joined dj
),
country_days_ranked AS (
    SELECT
        dj.country_name,
        dj.payment_date,
        dj.day_amount,
        ROW_NUMBER() OVER (
            PARTITION BY dj.country_name
            ORDER BY dj.day_amount
        ) AS rn,
        COUNT(*) OVER (PARTITION BY dj.country_name) AS cnt
    FROM daily_joined dj
),
country_p95 AS (
    SELECT
        country_name,
        MAX(day_amount) AS p95_day_amount
    FROM (
        SELECT
            country_name,
            day_amount,
            rn,
            cnt
        FROM country_days_ranked
        WHERE rn >= CAST((95.0 * cnt + 99) / 100 AS INT)
    )
    GROUP BY country_name
),
final_scored AS (
    SELECT
        dwp.customer_id,
        dwp.customer_name,
        dwp.city_name,
        dwp.country_name,
        dwp.payment_date,
        dwp.payment_count,
        dwp.day_amount,
        dwp.staff_count,
        dwp.store_count,
        dwp.personal_avg_prev_30d,
        (dwp.day_amount / dwp.personal_avg_prev_30d) AS exceed_ratio,
        cp.p95_day_amount,
        (dwp.day_amount - dwp.personal_avg_prev_30d) AS exceed_amount
    FROM daily_with_personal_avg dwp
    JOIN country_p95 cp
      ON cp.country_name = dwp.country_name
    WHERE dwp.personal_avg_prev_30d IS NOT NULL
      AND dwp.personal_avg_prev_30d > 0
      AND dwp.payment_count >= 3
      AND dwp.staff_count >= 2
      AND dwp.day_amount > 3.0 * dwp.personal_avg_prev_30d
      AND dwp.day_amount > cp.p95_day_amount
),
ranked_inside_country AS (
    SELECT
        fs.*,
        RANK() OVER (
            PARTITION BY fs.country_name
            ORDER BY fs.exceed_amount DESC, fs.day_amount DESC, fs.customer_id
        ) AS suspicion_rank_in_country
    FROM final_scored fs
)
SELECT
    customer_id,
    customer_name,
    city_name,
    country_name,
    payment_date,
    payment_count,
    ROUND(day_amount, 2) AS day_amount,
    staff_count,
    store_count,
    suspicion_rank_in_country
FROM ranked_inside_country
ORDER BY
    country_name,
    suspicion_rank_in_country,
    payment_date,
    customer_id;