WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        co.c02 AS customer_country,
        ci.d02 AS customer_city
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
),
payments_2005 AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        p.p03 AS staff_id,
        st.o07 AS staff_store_id,
        CAST(p.p05 AS REAL) AS amount
    FROM pay AS p
    JOIN stf AS st ON st.o01 = p.p03
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 <  '2006-01-01'
),
day_agg AS (
    SELECT
        p.customer_id,
        p.payment_date,
        cg.customer_country,
        COUNT(*) AS day_payment_count,
        SUM(p.amount) AS day_payment_amount,
        COUNT(DISTINCT p.staff_id) AS staff_count,
        COUNT(DISTINCT p.staff_store_id) AS store_count,
        GROUP_CONCAT(DISTINCT cs2.c02) AS store_countries,
        MAX(CASE WHEN cs2.c02 IS NOT NULL AND cs2.c02 <> cg.customer_country THEN 1 ELSE 0 END) AS has_foreign_store_payment
    FROM payments_2005 AS p
    JOIN customer_geo AS cg ON cg.customer_id = p.customer_id
    JOIN sto AS s2 ON s2.j01 = p.staff_store_id
    JOIN adr AS a2 ON a2.e01 = s2.j03
    JOIN cty AS ci2 ON ci2.d01 = a2.e05
    JOIN cnt AS cs2 ON cs2.c01 = ci2.d03
    GROUP BY
        p.customer_id,
        p.payment_date,
        cg.customer_country
),
day_with_hist AS (
    SELECT
        d.*,
        (
            SELECT AVG(dh.day_payment_amount)
            FROM day_agg AS dh
            WHERE dh.customer_id = d.customer_id
              AND dh.payment_date >= date(d.payment_date, '-30 days')
              AND dh.payment_date <  d.payment_date
        ) AS avg_prev_30d_amount
    FROM day_agg AS d
),
suspicious_days AS (
    SELECT
        dwh.*,
        (dwh.day_payment_amount / NULLIF(dwh.avg_prev_30d_amount, 0)) AS exceed_ratio
    FROM day_with_hist AS dwh
    WHERE dwh.avg_prev_30d_amount IS NOT NULL
      AND dwh.avg_prev_30d_amount > 0
      AND dwh.day_payment_count >= 3
      AND dwh.day_payment_amount >= 2.0 * dwh.avg_prev_30d_amount
      AND dwh.staff_count > 1
      AND dwh.store_count > 1
      AND dwh.has_foreign_store_payment = 1
),
ranked AS (
    SELECT
        sd.*,
        RANK() OVER (
            PARTITION BY sd.customer_country
            ORDER BY sd.exceed_ratio DESC, sd.day_payment_amount DESC, sd.customer_id, sd.payment_date
        ) AS suspicious_rank_within_country
    FROM suspicious_days AS sd
)
SELECT
    r.customer_id,
    cg.customer_country AS customer_country,
    cg.customer_city AS customer_city,
    r.payment_date AS suspicious_date,
    r.day_payment_count AS payment_count,
    ROUND(r.day_payment_amount, 2) AS day_payment_amount,
    ROUND(r.avg_prev_30d_amount, 2) AS avg_daily_amount_prev_30d,
    r.exceed_ratio AS exceed_ratio,
    r.staff_count AS distinct_staff_count,
    r.store_count AS distinct_store_count,
    r.store_countries AS store_countries,
    r.suspicious_rank_within_country AS suspicious_rank_in_customer_country
FROM ranked AS r
JOIN customer_geo AS cg
  ON cg.customer_id = r.customer_id
ORDER BY
    r.customer_country,
    r.suspicious_rank_in_customer_country,
    r.day_payment_amount DESC,
    r.customer_id,
    r.payment_date;