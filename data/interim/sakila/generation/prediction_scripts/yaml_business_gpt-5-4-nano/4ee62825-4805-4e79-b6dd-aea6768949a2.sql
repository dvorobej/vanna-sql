WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        ci.d02 AS city_name,
        co.c02 AS country_name,
        co.c01 AS country_id
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
),
daily_staff_shop AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        p.p03 AS staff_id,
        s.o07 AS store_id,
        CAST(p.p05 AS REAL) AS amount
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
),
daily_payments AS (
    SELECT
        dss.customer_id,
        dss.payment_date,
        SUM(dss.amount) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT dss.staff_id) AS staff_count,
        COUNT(DISTINCT dss.store_id) AS shop_count,
        MAX(dss.amount) AS max_payment,
        MIN(p2.p06) AS first_payment_ts,
        MAX(p2.p06) AS last_payment_ts
    FROM daily_staff_shop AS dss
    JOIN pay AS p2
      ON p2.p02 = dss.customer_id
     AND date(p2.p06) = dss.payment_date
     AND p2.p03 = (SELECT p3.p03 FROM pay AS p3 WHERE p3.p02 = dss.customer_id AND date(p3.p06)=dss.payment_date ORDER BY p3.p01 LIMIT 1)
    GROUP BY
        dss.customer_id,
        dss.payment_date
),
daily_with_personal_avg AS (
    SELECT
        dp.*,
        (
            SELECT COALESCE(SUM(dp_prev.day_amount), 0.0) / 30.0
            FROM daily_payments AS dp_prev
            WHERE dp_prev.customer_id = dp.customer_id
              AND dp_prev.payment_date >= date(dp.payment_date, '-30 day')
              AND dp_prev.payment_date < dp.payment_date
        ) AS personal_avg_prev_30d
    FROM daily_payments AS dp
),
country_p95 AS (
    SELECT
        t.country_id,
        t.payment_date,
        t.day_amount,
        t.rn,
        t.cnt,
        (CAST((0.95 * t.cnt + 0.999999) AS INTEGER)) AS p95_threshold_rn
    FROM (
        SELECT
            cg.country_id,
            dp.payment_date,
            dp.day_amount,
            ROW_NUMBER() OVER (PARTITION BY cg.country_id ORDER BY dp.day_amount) AS rn,
            COUNT(*) OVER (PARTITION BY cg.country_id) AS cnt
        FROM daily_with_personal_avg AS dp
        JOIN customer_geo AS cg
          ON cg.customer_id = dp.customer_id
    ) AS t
),
flagged_country_p95 AS (
    SELECT
        country_id,
        MAX(CASE WHEN rn >= CAST(0.95 * cnt AS INTEGER) THEN day_amount END) AS country_p95_day_amount
    FROM (
        SELECT
            country_id,
            payment_date,
            day_amount,
            rn,
            cnt
        FROM country_p95
    ) AS x
    GROUP BY country_id
),
suspicious AS (
    SELECT
        dp.customer_id,
        cg.customer_name,
        cg.city_name,
        cg.country_id,
        cg.country_name,
        dp.payment_date,
        dp.payment_count,
        dp.day_amount,
        dp.staff_count,
        dp.shop_count,
        dp.first_payment_ts,
        dp.last_payment_ts,
        dp.max_payment,
        dp.day_amount - dp.personal_avg_prev_30d AS deviation_from_personal_avg,
        CASE
            WHEN dp.personal_avg_prev_30d > 0 THEN dp.day_amount / dp.personal_avg_prev_30d
            ELSE NULL
        END AS exceed_ratio
    FROM daily_with_personal_avg AS dp
    JOIN customer_geo AS cg
      ON cg.customer_id = dp.customer_id
    JOIN flagged_country_p95 AS c95
      ON c95.country_id = cg.country_id
    WHERE dp.personal_avg_prev_30d > 0
      AND dp.payment_count >= 3
      AND dp.staff_count >= 2
      AND dp.day_amount > 2.0 * dp.personal_avg_prev_30d
      AND dp.day_amount >= c95.country_p95_day_amount
)
SELECT
    s.customer_id,
    s.customer_name,
    s.city_name,
    s.country_name,
    s.payment_date AS suspicious_day,
    s.payment_count,
    ROUND(s.day_amount, 2) AS day_amount,
    s.staff_count AS involved_staff_count,
    s.shop_count AS involved_shop_count,
    s.first_payment_ts AS first_payment_time,
    s.last_payment_ts AS last_payment_time,
    ROUND(s.max_payment, 2) AS max_payment_for_day,
    RANK() OVER (
        PARTITION BY s.country_id
        ORDER BY (s.exceed_ratio) DESC, s.day_amount DESC, s.customer_id
    ) AS suspicious_rank_in_country
FROM suspicious AS s
ORDER BY
    s.country_name,
    suspicious_rank_in_country,
    s.day_amount DESC,
    s.payment_date,
    s.customer_id;