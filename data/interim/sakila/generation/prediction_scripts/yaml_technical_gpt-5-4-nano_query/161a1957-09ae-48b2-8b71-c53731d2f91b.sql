WITH customer_geo AS (
    SELECT
        cus.h01 AS customer_id,
        cus.h03 || ' ' || cus.h04 AS customer_name,
        cnt.c02 AS country,
        cty.d02 AS city
    FROM cus
    JOIN adr  ON adr.e01 = cus.h06
    JOIN cty  ON cty.d01 = adr.e05
    JOIN cnt  ON cnt.c01 = cty.d03
),
pay_daily AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        GROUP_CONCAT(DISTINCT p.p03) AS staff_list
    FROM pay AS p
    GROUP BY p.p02, date(p.p06)
),
daily_with_staff_details AS (
    SELECT
        pd.*,
        (
            SELECT COUNT(DISTINCT p2.p03)
            FROM pay AS p2
            WHERE p2.p02 = pd.customer_id
              AND date(p2.p06) = pd.payment_date
        ) AS staff_distinct_cnt,
        (
            SELECT COUNT(DISTINCT st.o07)
            FROM pay AS p3
            JOIN stf AS st ON st.o01 = p3.p03
            WHERE p3.p02 = pd.customer_id
              AND date(p3.p06) = pd.payment_date
        ) AS store_distinct_cnt
    FROM pay_daily AS pd
),
daily_calendar_avg AS (
    SELECT
        d.customer_id,
        d.payment_date,
        d.payment_count,
        d.day_amount,
        d.staff_list,
        d.staff_distinct_cnt,
        d.store_distinct_cnt,
        (
            SELECT AVG(d2.day_amount)
            FROM pay_daily AS d2
            WHERE d2.customer_id = d.customer_id
              AND d2.payment_date >= date(d.payment_date, '-30 days')
              AND d2.payment_date < d.payment_date
        ) AS personal_avg_prev_30d
    FROM daily_with_staff_details AS d
),
country_daily AS (
    SELECT
        cg.country,
        dd.payment_date,
        dd.day_amount
    FROM daily_calendar_avg AS dd
    JOIN customer_geo AS cg
      ON cg.customer_id = dd.customer_id
),
country_daily_rank AS (
    SELECT
        country,
        payment_date,
        day_amount,
        ROW_NUMBER() OVER (
            PARTITION BY country, payment_date
            ORDER BY day_amount DESC
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY country, payment_date
        ) AS cnt_in_day
    FROM (
        SELECT DISTINCT country, payment_date, day_amount
        FROM country_daily
    )
),
country_p95_threshold AS (
    SELECT
        country,
        payment_date,
        MAX(CASE
              WHEN rn = CAST((0.95 * cnt_in_day + 0.999) AS INTEGER)
              THEN day_amount
            END
        ) AS p95_daily_amount
    FROM country_daily_rank
    GROUP BY country, payment_date
),
candidate AS (
    SELECT
        dca.customer_id,
        cg.country,
        cg.city,
        dca.payment_date,
        dca.payment_count,
        dca.day_amount,
        dca.personal_avg_prev_30d,
        (dca.day_amount - dca.personal_avg_prev_30d) AS deviation_from_personal_avg,
        dca.staff_list,
        dca.staff_distinct_cnt,
        dca.store_distinct_cnt,
        cpt.p95_daily_amount
    FROM daily_calendar_avg AS dca
    JOIN customer_geo AS cg
      ON cg.customer_id = dca.customer_id
    JOIN country_p95_threshold AS cpt
      ON cpt.country = cg.country
     AND cpt.payment_date = dca.payment_date
    WHERE dca.payment_count >= 3
      AND (dca.staff_distinct_cnt > 1 OR dca.store_distinct_cnt > 1)
      AND dca.personal_avg_prev_30d IS NOT NULL
      AND dca.personal_avg_prev_30d > 0
      AND dca.day_amount >= 2.0 * dca.personal_avg_prev_30d
      AND dca.day_amount > cpt.p95_daily_amount
)
SELECT
    customer_id,
    country,
    city,
    payment_date AS suspicious_date,
    payment_count,
    ROUND(day_amount, 2) AS day_amount,
    staff_list AS staff_list,
    ROUND(deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
    DENSE_RANK() OVER (
        PARTITION BY country
        ORDER BY deviation_from_personal_avg DESC
    ) AS country_suspicion_rank
FROM candidate
ORDER BY
    country,
    country_suspicion_rank,
    suspicious_date,
    customer_id;