WITH pay_daily AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS day_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS daily_amount,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT s.o07) AS distinct_store_count
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
        cnt.c02 AS country_name,
        cty.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a
      ON a.e01 = c.h06
    JOIN cty
      ON cty.d01 = a.e05
    JOIN cnt
      ON cnt.c01 = cty.d03
),
customer_day_with_history AS (
    SELECT
        pd.*,
        cg.country_name,
        cg.city_name,
        (
            SELECT AVG(pd_prev.daily_amount)
            FROM pay_daily AS pd_prev
            WHERE pd_prev.customer_id = pd.customer_id
              AND pd_prev.day_date >= date(pd.day_date, '-30 days')
              AND pd_prev.day_date < pd.day_date
        ) AS personal_avg_prev_30d
    FROM pay_daily AS pd
    JOIN customer_geo AS cg
      ON cg.customer_id = pd.customer_id
),
country_daily_avg AS (
    SELECT
        cdh.country_name,
        cdh.day_date,
        AVG(cdh.daily_amount) AS country_avg_daily_amount
    FROM customer_day_with_history AS cdh
    GROUP BY
        cdh.country_name,
        cdh.day_date
),
suspicious_days AS (
    SELECT
        cdh.customer_id,
        cdh.country_name,
        cdh.city_name,
        cdh.day_date AS suspicious_date,
        cdh.daily_amount,
        cdh.payment_count,
        cdh.distinct_staff_count,
        cdh.distinct_store_count,
        cdh.personal_avg_prev_30d,
        (cdh.daily_amount - cdh.personal_avg_prev_30d) AS deviation_from_personal_avg,
        (cdh.daily_amount - cda.country_avg_daily_amount) AS deviation_from_country_avg,
        cda.country_avg_daily_amount,
        ROW_NUMBER() OVER (
            PARTITION BY cdh.country_name, cdh.day_date
            ORDER BY cdh.daily_amount DESC
        ) AS suspicious_rank_in_country
    FROM customer_day_with_history AS cdh
    JOIN country_daily_avg AS cda
      ON cda.country_name = cdh.country_name
     AND cda.day_date = cdh.day_date
    WHERE cdh.personal_avg_prev_30d IS NOT NULL
      AND cdh.personal_avg_prev_30d > 0
      AND cdh.daily_amount > 3.0 * cdh.personal_avg_prev_30d
      AND cdh.daily_amount > cda.country_avg_daily_amount
      AND (cdh.distinct_staff_count > 1 OR cdh.distinct_store_count > 1)
)
SELECT
    customer_id,
    country_name AS country,
    city_name AS city,
    suspicious_date AS date,
    ROUND(daily_amount, 2) AS daily_amount,
    payment_count,
    ROUND(deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
    ROUND(deviation_from_country_avg, 2) AS deviation_from_country_avg,
    distinct_staff_count AS staff_count,
    distinct_store_count AS store_count,
    suspicious_rank_in_country AS suspicion_rank_in_country
FROM suspicious_days
ORDER BY
    country,
    suspicious_rank_in_country,
    suspicious_date,
    customer_id;