WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        co.c02 AS country_name,
        ci.d02 AS city_name
    FROM cus c
    JOIN adr a ON a.e01 = c.h06
    JOIN cty ci ON ci.d01 = a.e05
    JOIN cnt co ON co.c01 = ci.d03
),
daily_base AS (
    SELECT
        p.p02 AS customer_id,
        cg.country_name,
        cg.city_name,
        date(p.p06) AS payment_date,
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay p
    JOIN customer_geo cg ON cg.customer_id = p.p02
    JOIN stf s ON s.o01 = p.p03
    GROUP BY
        p.p02,
        cg.country_name,
        cg.city_name,
        date(p.p06)
),
daily_with_personal_avg AS (
    SELECT
        db.*,
        (
            SELECT AVG(dbo.day_amount)
            FROM daily_base dbo
            WHERE dbo.customer_id = db.customer_id
              AND dbo.payment_date >= date(db.payment_date, '-30 days')
              AND dbo.payment_date < db.payment_date
        ) AS personal_avg_prev_30d
    FROM daily_base db
),
country_daily_distribution AS (
    SELECT
        dwpa.*,
        PERCENT_RANK() OVER (
            PARTITION BY dwpa.country_name, dwpa.payment_date
            ORDER BY dwpa.day_amount
        ) AS pr
    FROM daily_with_personal_avg dwpa
),
country_daily_p95 AS (
    SELECT
        country_name,
        payment_date,
        MAX(day_amount) AS country_p95_day_amount
    FROM (
        SELECT
            cdd.*,
            ROW_NUMBER() OVER (
                PARTITION BY cdd.country_name
                ORDER BY cdd.day_amount DESC
            ) AS rn,
            COUNT(*) OVER (
                PARTITION BY cdd.country_name
            ) AS cnt
        FROM daily_with_personal_avg cdd
        WHERE cdd.personal_avg_prev_30d IS NOT NULL
    ) x
    WHERE rn >= CAST(((95.0/100.0) * cnt) + 0.999 AS INTEGER)
    GROUP BY country_name, payment_date
),
suspicious_days AS (
    SELECT
        dwpa.*,
        cdp.country_p95_day_amount,
        (dwpa.day_amount - dwpa.personal_avg_prev_30d) AS excess_over_personal_avg,
        RANK() OVER (
            PARTITION BY dwpa.country_name, dwpa.payment_date
            ORDER BY (dwpa.day_amount - dwpa.personal_avg_prev_30d) DESC
        ) AS suspicion_rank_in_country
    FROM daily_with_personal_avg dwpa
    JOIN country_daily_p95 cdp
      ON cdp.country_name = dwpa.country_name
     AND cdp.payment_date = dwpa.payment_date
    WHERE dwpa.personal_avg_prev_30d IS NOT NULL
      AND dwpa.payment_count >= 3
      AND (dwpa.staff_count >= 2 OR dwpa.store_count >= 2)
      AND dwpa.day_amount > 2.0 * dwpa.personal_avg_prev_30d
      AND dwpa.day_amount > cdp.country_p95_day_amount
)
SELECT
    sd.customer_id,
    sd.country_name,
    sd.city_name,
    sd.payment_date,
    sd.payment_count,
    ROUND(sd.day_amount, 2) AS day_amount,
    GROUP_CONCAT(DISTINCT p.p03) AS staff_ids,
    ROUND(sd.personal_avg_prev_30d, 2) AS personal_avg_prev_30d,
    ROUND(sd.excess_over_personal_avg, 2) AS deviation_from_personal_avg,
    sd.suspicion_rank_in_country
FROM suspicious_days sd
JOIN pay p
  ON p.p02 = sd.customer_id
 AND date(p.p06) = sd.payment_date
GROUP BY
    sd.customer_id,
    sd.country_name,
    sd.city_name,
    sd.payment_date,
    sd.payment_count,
    sd.day_amount,
    sd.personal_avg_prev_30d,
    sd.excess_over_personal_avg,
    sd.suspicion_rank_in_country
ORDER BY
    sd.country_name,
    sd.payment_date,
    sd.suspicion_rank_in_country,
    sd.day_amount DESC,
    sd.customer_id;