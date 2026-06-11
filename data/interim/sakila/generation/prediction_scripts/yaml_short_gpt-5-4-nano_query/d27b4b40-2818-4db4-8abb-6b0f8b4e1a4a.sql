WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        co.c02 AS country_name,
        ct.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ct ON ct.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ct.d03
),
daily AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_sum,
        COUNT(DISTINCT p.p03) AS staff_cnt,
        COUNT(DISTINCT COALESCE(p.p04, -1)) AS rental_cnt,
        COUNT(DISTINCT s.o07) AS store_cnt
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    GROUP BY
        p.p02,
        date(p.p06)
),
daily_with_hist AS (
    SELECT
        d.*,
        (
            SELECT AVG(CAST(d2.day_sum AS REAL))
            FROM daily AS d2
            WHERE d2.customer_id = d.customer_id
              AND d2.payment_date >= date(d.payment_date, '-30 days')
              AND d2.payment_date < d.payment_date
        ) AS avg_prev_30d
    FROM daily AS d
),
suspicious AS (
    SELECT
        dwh.*,
        (dwh.day_sum / NULLIF(dwh.avg_prev_30d, 0)) AS exceed_coeff
    FROM daily_with_hist AS dwh
    WHERE dwh.avg_prev_30d IS NOT NULL
      AND dwh.avg_prev_30d > 0
      AND dwh.payment_count >= 3
      AND dwh.day_sum >= 3.0 * dwh.avg_prev_30d
      AND (dwh.staff_cnt >= 2 OR dwh.store_cnt >= 2)
),
ranked AS (
    SELECT
        s.*,
        RANK() OVER (
            PARTITION BY s.customer_id
            ORDER BY s.day_sum DESC, s.payment_date
        ) AS day_rank_by_sum
    FROM suspicious AS s
)
SELECT
    r.customer_id,
    cg.customer_name,
    cg.country_name,
    cg.city_name,
    r.payment_date,
    r.payment_count,
    ROUND(r.day_sum, 2) AS total_payment_sum,
    ROUND(r.avg_prev_30d, 2) AS avg_daily_sum_prev_30d,
    ROUND(r.exceed_coeff, 3) AS exceed_coeff,
    r.day_rank_by_sum
FROM ranked AS r
JOIN customer_geo AS cg
  ON cg.customer_id = r.customer_id
ORDER BY
    cg.country_name,
    cg.city_name,
    r.customer_id,
    r.day_rank_by_sum,
    r.payment_date;