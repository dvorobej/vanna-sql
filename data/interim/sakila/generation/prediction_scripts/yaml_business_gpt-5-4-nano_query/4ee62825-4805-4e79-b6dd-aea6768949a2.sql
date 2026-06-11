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
),
daily_payments AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        cg.country_name,
        cg.city_name,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT st.o07) AS store_count,
        MIN(p.p06) AS first_payment_ts,
        MAX(p.p06) AS last_payment_ts,
        MAX(CAST(p.p05 AS REAL)) AS max_payment_amount
    FROM pay AS p
    JOIN stf AS st ON st.o01 = p.p03
    JOIN customer_geo AS cg ON cg.customer_id = p.p02
    GROUP BY
        p.p02,
        date(p.p06),
        cg.country_name,
        cg.city_name
),
daily_with_avgs AS (
    SELECT
        dp.*,
        (
            SELECT AVG(CAST(prev.day_amount AS REAL))
            FROM daily_payments AS prev
            WHERE prev.customer_id = dp.customer_id
              AND prev.payment_date >= date(dp.payment_date, '-30 day')
              AND prev.payment_date < dp.payment_date
        ) AS personal_avg_prev_30d,
        (
            SELECT AVG(CAST(dpc.day_amount AS REAL))
            FROM daily_payments AS dpc
            WHERE dpc.country_name = dp.country_name
              AND dpc.payment_date = dp.payment_date
        ) AS country_avg_same_day
    FROM daily_payments AS dp
),
country_p95 AS (
    -- 95-й перцентиль по дневным суммам среди клиентов страны (для каждой страны берем порог по всем датам)
    SELECT country_name, day_amount AS p95_day_amount
    FROM (
        SELECT
            dp.country_name,
            dp.day_amount,
            ROW_NUMBER() OVER (
                PARTITION BY dp.country_name
                ORDER BY dp.day_amount
            ) AS rn,
            COUNT(*) OVER (PARTITION BY dp.country_name) AS cnt
        FROM daily_payments AS dp
    ) t
    WHERE rn = CAST(CEIL(0.95 * cnt) AS INTEGER)
),
flagged AS (
    SELECT
        d.*,
        cp.p95_day_amount,
        d.day_amount - d.personal_avg_prev_30d AS excess_over_personal_avg,
        ROW_NUMBER() OVER (
            PARTITION BY d.country_name
            ORDER BY (d.day_amount - d.personal_avg_prev_30d) DESC, d.day_amount DESC
        ) AS suspicion_rank
    FROM daily_with_avgs AS d
    JOIN country_p95 AS cp ON cp.country_name = d.country_name
    WHERE d.personal_avg_prev_30d IS NOT NULL
      AND d.personal_avg_prev_30d > 0
      AND d.payment_count >= 3
      AND d.staff_count >= 2
      AND d.day_amount > 3.0 * d.personal_avg_prev_30d
      AND d.day_amount > cp.p95_day_amount
      AND EXISTS (
          SELECT 1
          FROM cus c
          WHERE c.h01 = d.customer_id
            AND c.h07 = 'Y'
      )
)
SELECT
    f.customer_id,
    f.country_name,
    f.city_name,
    f.payment_date,
    f.payment_count,
    ROUND(f.day_amount, 2) AS day_amount,
    f.staff_count,
    f.store_count,
    f.first_payment_ts,
    f.last_payment_ts,
    ROUND(f.max_payment_amount, 2) AS max_payment_amount,
    ROUND(f.excess_over_personal_avg, 2) AS excess_over_personal_avg,
    f.suspicion_rank AS suspicion_rank_in_country
FROM flagged AS f
ORDER BY
    f.country_name,
    f.suspicion_rank,
    f.payment_date,
    f.customer_id;