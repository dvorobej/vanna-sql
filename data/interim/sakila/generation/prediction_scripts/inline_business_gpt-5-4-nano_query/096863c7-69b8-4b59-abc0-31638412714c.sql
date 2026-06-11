WITH payment_daily AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p03 AS staff_id,
        p.p04 AS rental_id
    FROM pay AS p
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        ct.c02 AS country,
        ci.d02 AS city
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ci
        ON ci.d01 = a.e05
    JOIN cnt AS ct
        ON ct.c01 = ci.d03
),
daily_agg AS (
    SELECT
        pd.customer_id,
        cg.country,
        cg.city,
        pd.payment_date,
        COUNT(*) AS payment_count,
        SUM(pd.payment_amount) AS day_sum,
        COUNT(DISTINCT pd.staff_id) AS staff_count
    FROM payment_daily pd
    JOIN customer_geo cg
        ON cg.customer_id = pd.customer_id
    GROUP BY
        pd.customer_id, cg.country, cg.city, pd.payment_date
),
daily_with_personal_avg AS (
    SELECT
        da.*,
        (
            SELECT AVG(da_prev.day_sum)
            FROM daily_agg AS da_prev
            WHERE da_prev.customer_id = da.customer_id
              AND da_prev.payment_date >= date(da.payment_date, '-30 day')
              AND da_prev.payment_date < da.payment_date
        ) AS personal_avg_daily_prev_30
    FROM daily_agg AS da
),
daily_with_country_avg AS (
    SELECT
        dwp.*,
        (
            SELECT AVG(dac2.day_sum)
            FROM daily_agg AS dac2
            WHERE dac2.country = dwp.country
              AND dac2.payment_date >= date(dwp.payment_date, '-30 day')
              AND dac2.payment_date < dwp.payment_date
        ) AS country_avg_daily_prev_30
    FROM daily_with_personal_avg AS dwp
),
suspicious_days AS (
    SELECT
        dwp.customer_id,
        dwp.country,
        dwp.city,
        dwp.payment_date,
        dwp.payment_count,
        dwp.day_sum,
        dwp.personal_avg_daily_prev_30,
        dwp.country_avg_daily_prev_30,
        (dwp.day_sum - dwp.personal_avg_daily_prev_30) AS deviation_personal,
        (dwp.day_sum - dwp.country_avg_daily_prev_30) AS deviation_country,
        dwp.staff_count,
        /* Different shops proxy: number of distinct stores cannot be derived from provided schema here.
           Use staff_count>=2 as the "different employees" / "different shops" indicator as required by schema. */
        dwp.staff_count AS distinct_stores_proxy
    FROM daily_with_country_avg dwp
    WHERE dwp.personal_avg_daily_prev_30 IS NOT NULL
      AND dwp.personal_avg_daily_prev_30 > 0
      AND dwp.country_avg_daily_prev_30 IS NOT NULL
      AND dwp.country_avg_daily_prev_30 > 0
      AND dwp.day_sum > 3.0 * dwp.personal_avg_daily_prev_30
      AND dwp.day_sum > dwp.country_avg_daily_prev_30
      AND dwp.staff_count >= 2
)
SELECT
    sd.customer_id,
    sd.country,
    sd.city,
    sd.payment_date,
    sd.day_sum AS total_day_sum,
    sd.payment_count,
    sd.deviation_personal AS deviation_from_personal_avg,
    sd.deviation_country AS deviation_from_country_avg,
    sd.staff_count AS distinct_staff_count,
    sd.distinct_stores_proxy AS distinct_stores_count_proxy,
    RANK() OVER (
        PARTITION BY sd.country, sd.payment_date
        ORDER BY sd.day_sum DESC
    ) AS suspicious_amount_rank_in_country
FROM suspicious_days sd
ORDER BY
    sd.country,
    sd.payment_date,
    sd.day_sum DESC,
    sd.customer_id;