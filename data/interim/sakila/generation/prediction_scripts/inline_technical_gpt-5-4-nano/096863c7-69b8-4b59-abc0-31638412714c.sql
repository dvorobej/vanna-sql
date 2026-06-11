WITH payment_daily AS (
    SELECT
        c.h01 AS customer_id,
        c.h06 AS customer_address_id,
        c.h02 AS customer_store_id,
        cnt.c02 AS country_name,
        cty.d02 AS city_name,
        DATE(p.p06) AS payment_day,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT inv.n03) AS distinct_store_count
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS cty
        ON cty.d01 = a.e05
    JOIN cnt AS cnt
        ON cnt.c01 = cty.d03
    LEFT JOIN ren AS r
        ON r.q01 = p.p04
    LEFT JOIN inv AS inv
        ON inv.n01 = r.q03
    WHERE p.p06 IS NOT NULL
    GROUP BY
        c.h01, cnt.c02, cty.d02,
        DATE(p.p06)
),
daily_with_baselines AS (
    SELECT
        pd.*,
        (
            SELECT AVG(pd_prev.day_amount)
            FROM payment_daily AS pd_prev
            WHERE pd_prev.customer_id = pd.customer_id
              AND pd_prev.payment_day >= DATE(pd.payment_day, '-30 days')
              AND pd_prev.payment_day < pd.payment_day
        ) AS personal_avg_prev_30d,
        (
            SELECT AVG(pd_country.day_amount)
            FROM payment_daily AS pd_country
            WHERE pd_country.country_name = pd.country_name
              AND pd_country.payment_day >= DATE(pd.payment_day, '-30 days')
              AND pd_country.payment_day < pd.payment_day
        ) AS country_avg_prev_30d
    FROM payment_daily AS pd
),
filtered AS (
    SELECT
        dwb.*,
        (dwb.day_amount - dwb.personal_avg_prev_30d) AS deviation_personal,
        (dwb.day_amount - dwb.country_avg_prev_30d) AS deviation_country
    FROM daily_with_baselines AS dwb
    WHERE dwb.personal_avg_prev_30d IS NOT NULL
      AND dwb.country_avg_prev_30d IS NOT NULL
      AND dwb.personal_avg_prev_30d > 0
      AND dwb.country_avg_prev_30d > 0
      AND dwb.day_amount > 3.0 * dwb.personal_avg_prev_30d
      AND dwb.day_amount > dwb.country_avg_prev_30d
)
SELECT
    f.customer_id AS h01,
    f.country_name AS c02,
    f.city_name AS d02,
    f.payment_day AS payment_date,
    ROUND(f.day_amount, 2) AS day_amount,
    f.payment_count AS payment_count,
    ROUND(f.deviation_personal, 2) AS deviation_personal_avg,
    ROUND(f.deviation_country, 2) AS deviation_country_avg,
    f.distinct_staff_count AS distinct_staff_o01,
    f.distinct_store_count AS distinct_stores_j01,
    RANK() OVER (
        PARTITION BY f.country_name
        ORDER BY f.day_amount DESC, f.customer_id
    ) AS suspicion_rank_in_country
FROM filtered AS f
ORDER BY
    f.country_name,
    suspicion_rank_in_country,
    f.payment_date,
    f.customer_id;