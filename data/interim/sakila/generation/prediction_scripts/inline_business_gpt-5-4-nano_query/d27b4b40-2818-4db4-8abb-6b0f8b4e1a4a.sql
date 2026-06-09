WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        co.c02 AS country,
        ci.d02 AS city
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
),
daily_customer_pay AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_total_amount,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT st.o07) AS distinct_store_count
    FROM pay AS p
    JOIN stf AS st ON st.o01 = p.p03
    GROUP BY
        p.p02,
        date(p.p06)
),
daily_with_prev_avg AS (
    SELECT
        d.customer_id,
        d.payment_date,
        d.payment_count,
        d.day_total_amount,
        d.distinct_staff_count,
        d.distinct_store_count,
        (
            SELECT AVG(CAST(p30.p05 AS REAL))
            FROM pay AS p30
            WHERE p30.p02 = d.customer_id
              AND p30.p06 >= datetime(d.payment_date, '-30 days')
              AND p30.p06 < datetime(d.payment_date)
        ) * 30.0 AS avg_daily_amount_prev_30_days
    FROM daily_customer_pay AS d
),
suspicious_days AS (
    SELECT
        d.customer_id,
        d.payment_date,
        d.payment_count,
        d.day_total_amount,
        d.avg_daily_amount_prev_30_days,
        d.day_total_amount / NULLIF(d.avg_daily_amount_prev_30_days, 0) AS exceed_factor
    FROM daily_with_prev_avg AS d
    WHERE d.avg_daily_amount_prev_30_days IS NOT NULL
      AND d.avg_daily_amount_prev_30_days > 0
      AND d.day_total_amount >= 3.0 * d.avg_daily_amount_prev_30_days
      AND d.payment_count >= 3
      AND (d.distinct_staff_count >= 2 OR d.distinct_store_count >= 2)
),
ranked_days AS (
    SELECT
        sd.*,
        RANK() OVER (
            PARTITION BY sd.customer_id
            ORDER BY sd.day_total_amount DESC
        ) AS day_rank_by_amount
    FROM suspicious_days AS sd
)
SELECT
    rd.customer_id,
    cg.country,
    cg.city,
    rd.payment_date,
    rd.payment_count,
    ROUND(rd.day_total_amount, 2) AS total_amount,
    ROUND(rd.avg_daily_amount_prev_30_days, 2) AS avg_daily_amount_prev_30_days,
    ROUND(rd.exceed_factor, 4) AS exceed_factor,
    rd.day_rank_by_amount
FROM ranked_days AS rd
JOIN customer_geo AS cg
  ON cg.customer_id = rd.customer_id
ORDER BY
    rd.customer_id,
    rd.day_rank_by_amount,
    rd.payment_date;