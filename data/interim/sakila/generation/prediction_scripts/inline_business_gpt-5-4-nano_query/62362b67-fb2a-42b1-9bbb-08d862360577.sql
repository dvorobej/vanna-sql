WITH daily AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS suspicious_date,
        SUM(p.p05) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count
    FROM pay AS p
    JOIN stf AS s
        ON s.o01 = p.p03
    GROUP BY
        p.p02,
        date(p.p06)
),
daily_with_history AS (
    SELECT
        d.*,
        (
            SELECT AVG(dh.day_amount)
            FROM daily AS dh
            WHERE dh.customer_id = d.customer_id
              AND dh.suspicious_date >= date(d.suspicious_date, '-30 days')
              AND dh.suspicious_date < d.suspicious_date
        ) AS avg_prev_30d
    FROM daily AS d
),
filtered AS (
    SELECT
        dwh.*,
        (dwh.day_amount - dwh.avg_prev_30d) / NULLIF(dwh.avg_prev_30d, 0) AS exceed_ratio
    FROM daily_with_history AS dwh
    WHERE dwh.avg_prev_30d IS NOT NULL
      AND dwh.avg_prev_30d > 0
      AND dwh.day_amount >= 3.0 * dwh.avg_prev_30d
      AND (dwh.staff_count > 1 OR dwh.store_count > 1)
),
client_geo AS (
    SELECT
        c.h01 AS customer_id,
        cn.c02 AS country_name,
        ci.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ci
        ON ci.d01 = a.e05
    JOIN cnt AS cn
        ON cn.c01 = ci.d03
)
SELECT
    f.customer_id,
    cg.country_name,
    cg.city_name,
    f.suspicious_date AS suspicious_date,
    ROUND(f.day_amount, 2) AS day_amount,
    f.payment_count,
    f.staff_count AS staff_count,
    ROUND(f.avg_prev_30d, 2) AS avg_prev_30d,
    RANK() OVER (
        ORDER BY f.exceed_ratio DESC
    ) AS suspicion_rank
FROM filtered AS f
JOIN client_geo AS cg
    ON cg.customer_id = f.customer_id
JOIN cus AS c
    ON c.h01 = f.customer_id
ORDER BY
    suspicion_rank,
    f.suspicious_date,
    f.customer_id;