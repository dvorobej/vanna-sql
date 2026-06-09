WITH pay_daily AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS pay_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS daily_amount
    FROM pay p
    GROUP BY p.p02, date(p.p06)
),
pay_daily_details AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS pay_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS daily_amount,
        GROUP_CONCAT(DISTINCT p.p03) AS staff_ids,
        COUNT(DISTINCT p.p03) AS staff_count,
        GROUP_CONCAT(DISTINCT s.o07) AS store_ids,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay p
    JOIN stf s ON s.o01 = p.p03
    GROUP BY p.p02, date(p.p06)
),
customer_geo AS (
    SELECT
        cus.h01 AS customer_id,
        cnt.c02 AS country,
        cty.d02 AS city
    FROM cus
    JOIN adr  ON adr.e01 = cus.h06
    JOIN cty  ON cty.d01 = adr.e05
    JOIN cnt  ON cnt.c01 = cty.d03
),
daily_with_personal_avg AS (
    SELECT
        ddd.customer_id,
        ddd.pay_date,
        ddd.payment_count,
        ddd.daily_amount,
        ddd.staff_ids,
        ddd.staff_count,
        ddd.store_ids,
        ddd.store_count,
        (
            SELECT AVG(pd.daily_amount)
            FROM pay_daily pd
            WHERE pd.customer_id = ddd.customer_id
              AND pd.pay_date >= date(ddd.pay_date, '-30 day')
              AND pd.pay_date <  ddd.pay_date
        ) AS avg_prev_30d
    FROM pay_daily_details ddd
),
country_daily_rank AS (
    SELECT
        cg.country,
        pd.customer_id,
        pd.pay_date,
        pd.daily_amount,
        ROW_NUMBER() OVER (
            PARTITION BY cg.country, pd.pay_date
            ORDER BY pd.daily_amount
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY cg.country, pd.pay_date
        ) AS cnt
    FROM pay_daily pd
    JOIN customer_geo cg ON cg.customer_id = pd.customer_id
),
country_p95_per_day AS (
    SELECT
        country,
        pay_date,
        MIN(daily_amount) AS p95_daily_amount
    FROM country_daily_rank
    WHERE rn >= CAST((95 * cnt + 99) / 100 AS INTEGER)
    GROUP BY country, pay_date
),
candidate_spikes AS (
    SELECT
        dw.customer_id,
        cg.country,
        cg.city,
        dw.pay_date,
        dw.payment_count,
        dw.daily_amount,
        dw.staff_ids,
        (dw.daily_amount - dw.avg_prev_30d) AS deviation_from_personal_avg,
        DENSE_RANK() OVER (
            PARTITION BY cg.country, dw.pay_date
            ORDER BY (dw.daily_amount - dw.avg_prev_30d) DESC
        ) AS suspicion_rank_in_country
    FROM daily_with_personal_avg dw
    JOIN customer_geo cg ON cg.customer_id = dw.customer_id
    JOIN country_p95_per_day cp
      ON cp.country = cg.country
     AND cp.pay_date = dw.pay_date
    WHERE dw.payment_count >= 3
      AND (dw.staff_count >= 2 OR dw.store_count >= 2)
      AND dw.avg_prev_30d IS NOT NULL
      AND dw.avg_prev_30d > 0
      AND dw.daily_amount >= 2 * dw.avg_prev_30d
      AND dw.daily_amount > cp.p95_daily_amount
)
SELECT
    customer_id,
    country,
    city,
    pay_date AS spike_date,
    payment_count,
    ROUND(daily_amount, 2) AS daily_amount,
    staff_ids,
    ROUND(deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
    suspicion_rank_in_country
FROM candidate_spikes
ORDER BY
    country,
    suspicion_rank_in_country,
    spike_date,
    customer_id;