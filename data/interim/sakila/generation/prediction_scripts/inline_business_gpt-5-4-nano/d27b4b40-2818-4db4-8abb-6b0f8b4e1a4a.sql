WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        co.c02 AS country_name,
        ct.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a
      ON a.e01 = c.h06
    JOIN cty AS ct
      ON ct.d01 = a.e05
    JOIN cnt AS co
      ON co.c01 = ct.d03
),
pay_base AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        s.o07 AS store_id,
        p.p04 AS rental_id,
        date(p.p06) AS payment_date,
        CAST(p.p05 AS REAL) AS amount
    FROM pay AS p
    JOIN stf AS s
      ON s.o01 = p.p03
),
daily_customer AS (
    SELECT
        pb.customer_id,
        pb.payment_date,
        COUNT(*) AS payment_count,
        SUM(pb.amount) AS day_sum,
        MAX(pb.amount) AS max_payment,
        COUNT(DISTINCT pb.staff_id) AS staff_count,
        COUNT(DISTINCT pb.store_id) AS store_count
    FROM pay_base AS pb
    GROUP BY
        pb.customer_id,
        pb.payment_date
),
daily_with_history AS (
    SELECT
        dc.*,
        (
            SELECT AVG(dc_prev.day_sum)
            FROM daily_customer AS dc_prev
            WHERE dc_prev.customer_id = dc.customer_id
              AND dc_prev.payment_date >= date(dc.payment_date, '-30 days')
              AND dc_prev.payment_date < dc.payment_date
        ) AS avg_prev_30d
    FROM daily_customer AS dc
),
suspicious_days AS (
    SELECT
        dwh.*,
        (dwh.day_sum / NULLIF(dwh.avg_prev_30d, 0)) AS exceed_coeff
    FROM daily_with_history AS dwh
    WHERE dwh.avg_prev_30d IS NOT NULL
      AND dwh.avg_prev_30d > 0
      AND dwh.payment_count >= 3
      AND (dwh.staff_count >= 2 OR dwh.store_count >= 2)
      AND dwh.day_sum >= 3.0 * dwh.avg_prev_30d
),
ranked_days AS (
    SELECT
        sd.*,
        RANK() OVER (
            PARTITION BY sd.customer_id
            ORDER BY sd.day_sum DESC, sd.payment_date ASC
        ) AS day_rank_by_sum
    FROM suspicious_days AS sd
)
SELECT
    rd.customer_id,
    cg.country_name,
    cg.city_name,
    rd.payment_date,
    rd.payment_count,
    ROUND(rd.day_sum, 2) AS day_sum,
    ROUND(rd.avg_prev_30d, 2) AS avg_prev_30d,
    ROUND(rd.exceed_coeff, 4) AS exceed_coeff,
    rd.staff_count,
    rd.store_count,
    rd.day_rank_by_sum
FROM ranked_days AS rd
JOIN customer_geo AS cg
  ON cg.customer_id = rd.customer_id
ORDER BY
    rd.customer_id,
    rd.day_rank_by_sum,
    rd.payment_date;