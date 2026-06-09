WITH payment_days AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        SUM(p.p05) AS daily_amount,
        COUNT(*) AS payment_count
    FROM pay AS p
    GROUP BY
        p.p02,
        date(p.p06)
),
payment_days_staff_store AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT COALESCE(s.o07, -1)) AS store_count
    FROM pay AS p
    JOIN stf AS s
        ON s.o01 = p.p03
    GROUP BY
        p.p02,
        date(p.p06)
),
customer_history AS (
    SELECT
        pd.customer_id,
        pd.payment_date,
        pd.daily_amount,
        pd.payment_count,
        COALESCE((
            SELECT AVG(pdh.daily_amount)
            FROM payment_days AS pdh
            WHERE pdh.customer_id = pd.customer_id
              AND pdh.payment_date >= date(pd.payment_date, '-30 days')
              AND pdh.payment_date < pd.payment_date
        ), 0.0) AS avg_daily_prev_30d
    FROM payment_days AS pd
),
suspicious AS (
    SELECT
        ch.customer_id,
        ch.payment_date,
        ch.daily_amount,
        ch.payment_count,
        ch.avg_daily_prev_30d,
        (ch.daily_amount / NULLIF(ch.avg_daily_prev_30d, 0.0)) AS exceed_ratio
    FROM customer_history AS ch
    JOIN payment_days_staff_store AS ds
        ON ds.customer_id = ch.customer_id
       AND ds.payment_date = ch.payment_date
    WHERE ch.avg_daily_prev_30d > 0
      AND ch.daily_amount >= 3.0 * ch.avg_daily_prev_30d
      AND (ds.staff_count >= 2 OR ds.store_count >= 2)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        cnt.c02 AS country_name,
        ci.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ci
        ON ci.d01 = a.e05
    JOIN cnt
        ON cnt.c01 = ci.d03
)
SELECT
    s.customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cg.country_name,
    cg.city_name,
    s.payment_date AS suspicious_date,
    ROUND(s.daily_amount, 2) AS daily_amount,
    s.payment_count,
    (SELECT COUNT(DISTINCT p.p03)
     FROM pay p
     WHERE p.p02 = s.customer_id
       AND date(p.p06) = s.payment_date) AS staff_count,
    ROUND(s.avg_daily_prev_30d, 2) AS avg_daily_prev_30d,
    RANK() OVER (
        ORDER BY (s.daily_amount - s.avg_daily_prev_30d) DESC,
                 s.daily_amount DESC,
                 s.customer_id
    ) AS suspicious_rank
FROM suspicious AS s
JOIN cus AS c
    ON c.h01 = s.customer_id
JOIN customer_geo AS cg
    ON cg.customer_id = s.customer_id
ORDER BY
    suspicious_rank,
    s.payment_date,
    s.customer_id;