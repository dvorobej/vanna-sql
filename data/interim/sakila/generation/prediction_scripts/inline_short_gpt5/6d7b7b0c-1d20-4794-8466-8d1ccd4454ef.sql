WITH raw_payments AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        stf.o02 || ' ' || stf.o03 AS staff_name,
        stf.o07 AS store_id,
        datetime(p.p06) AS payment_ts,
        CAST(p.p05 AS REAL) AS amount
    FROM pay AS p
    JOIN stf AS stf
        ON stf.o01 = p.p03
),
rolling_24h AS (
    SELECT
        anchor.payment_id AS last_payment_id,
        anchor.customer_id,
        anchor.staff_id AS last_staff_id,
        anchor.staff_name AS last_staff_name,
        anchor.store_id AS last_store_id,
        datetime(anchor.payment_ts, '-24 hours') AS window_start_ts,
        anchor.payment_ts AS window_end_ts,
        COUNT(rp.payment_id) AS window_payment_count,
        SUM(rp.amount) AS window_payment_amount
    FROM raw_payments AS anchor
    JOIN raw_payments AS rp
        ON rp.customer_id = anchor.customer_id
       AND rp.payment_ts > datetime(anchor.payment_ts, '-24 hours')
       AND (
            rp.payment_ts < anchor.payment_ts
            OR (
                rp.payment_ts = anchor.payment_ts
                AND rp.payment_id <= anchor.payment_id
            )
       )
    GROUP BY
        anchor.payment_id,
        anchor.customer_id,
        anchor.staff_id,
        anchor.staff_name,
        anchor.store_id,
        anchor.payment_ts
),
rolling_with_norm AS (
    SELECT
        r.*,
        (
            SELECT COALESCE(SUM(h.amount), 0) / 30.0
            FROM raw_payments AS h
            WHERE h.customer_id = r.customer_id
              AND h.payment_ts >= datetime(r.window_start_ts, '-30 days')
              AND h.payment_ts < r.window_start_ts
        ) AS avg_30d_daily_amount,
        (
            SELECT COUNT(*) / 30.0
            FROM raw_payments AS h
            WHERE h.customer_id = r.customer_id
              AND h.payment_ts >= datetime(r.window_start_ts, '-30 days')
              AND h.payment_ts < r.window_start_ts
        ) AS avg_30d_daily_count
    FROM rolling_24h AS r
),
customer_geo AS (
    SELECT
        cus.h01 AS customer_id,
        cus.h03 || ' ' || cus.h04 AS customer_name,
        cus.h05 AS email,
        cty.d02 AS city,
        cnt.c02 AS country
    FROM cus AS cus
    JOIN adr AS adr
        ON adr.e01 = cus.h06
    JOIN cty AS cty
        ON cty.d01 = adr.e05
    JOIN cnt AS cnt
        ON cnt.c01 = cty.d03
),
anomalies AS (
    SELECT
        rwn.customer_id,
        cg.customer_name,
        cg.email,
        cg.city,
        cg.country,
        rwn.window_start_ts,
        rwn.window_end_ts,
        rwn.last_payment_id,
        rwn.last_staff_id,
        rwn.last_staff_name,
        rwn.last_store_id,
        rwn.window_payment_count,
        rwn.window_payment_amount,
        rwn.avg_30d_daily_amount,
        rwn.avg_30d_daily_count,
        rwn.window_payment_amount - rwn.avg_30d_daily_amount AS amount_deviation,
        rwn.window_payment_count - rwn.avg_30d_daily_count AS count_deviation,
        rwn.window_payment_amount / NULLIF(rwn.avg_30d_daily_amount, 0) AS amount_to_norm_ratio,
        rwn.window_payment_count / NULLIF(rwn.avg_30d_daily_count, 0) AS count_to_norm_ratio
    FROM rolling_with_norm AS rwn
    JOIN customer_geo AS cg
        ON cg.customer_id = rwn.customer_id
    WHERE rwn.avg_30d_daily_amount > 0
      AND (
            rwn.window_payment_amount >= rwn.avg_30d_daily_amount * 3
            OR (
                rwn.avg_30d_daily_count > 0
                AND rwn.window_payment_count >= rwn.avg_30d_daily_count * 3
            )
      )
)
SELECT
    customer_id,
    customer_name,
    email,
    country,
    city,
    window_start_ts,
    window_end_ts,
    last_payment_id,
    last_staff_id,
    last_staff_name,
    last_store_id,
    window_payment_count,
    ROUND(window_payment_amount, 2) AS window_payment_amount,
    ROUND(avg_30d_daily_amount, 2) AS avg_30d_daily_amount,
    ROUND(avg_30d_daily_count, 2) AS avg_30d_daily_count,
    ROUND(amount_deviation, 2) AS amount_deviation,
    ROUND(count_deviation, 2) AS count_deviation,
    ROUND(amount_to_norm_ratio, 2) AS amount_to_norm_ratio,
    ROUND(count_to_norm_ratio, 2) AS count_to_norm_ratio,
    RANK() OVER (
        ORDER BY amount_deviation DESC, count_deviation DESC, window_payment_amount DESC
    ) AS anomaly_rank
FROM anomalies
ORDER BY
    anomaly_rank,
    window_end_ts,
    customer_id;