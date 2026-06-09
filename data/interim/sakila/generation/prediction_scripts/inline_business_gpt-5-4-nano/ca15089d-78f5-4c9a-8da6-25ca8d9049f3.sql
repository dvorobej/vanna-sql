WITH payment_base AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p06 AS payment_ts,
        date(p.p06, 'start of month') AS month_start,
        CAST(p.p05 AS REAL) AS amount,
        p.p03 AS staff_id,
        sf.o07 AS staff_store_id
    FROM pay AS p
    JOIN stf AS sf
      ON sf.o01 = p.p03
),
payment_month AS (
    SELECT
        pb.customer_id,
        pb.month_start,
        COUNT(pb.payment_id) AS payment_count,
        SUM(pb.amount) AS month_amount,
        MAX(pb.amount) AS max_payment,
        SUM(CASE WHEN pb.amount > 0 THEN pb.amount ELSE 0 END) AS month_amount_check,
        COUNT(DISTINCT pb.staff_id) AS staff_count,
        COUNT(DISTINCT pb.staff_store_id) AS store_count
    FROM payment_base AS pb
    GROUP BY
        pb.customer_id,
        pb.month_start
),
monthly_with_history AS (
    SELECT
        pm.*,
        AVG(pm.month_amount) OVER (
            PARTITION BY pm.customer_id
            ORDER BY pm.month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS avg_prev_month_amount,
        COUNT(*) OVER (
            PARTITION BY pm.customer_id
            ORDER BY pm.month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_months_count
    FROM payment_month AS pm
),
country_city AS (
    SELECT
        c.h01 AS customer_id,
        cnt.c02 AS country,
        cty.d02 AS city
    FROM cus AS c
    JOIN adr AS a
      ON a.e01 = c.h06
    JOIN cty
      ON cty.d01 = a.e05
    JOIN cnt
      ON cnt.c01 = cty.d03
),
qualifying AS (
    SELECT
        mwh.*,
        (mwh.max_payment / NULLIF(mwh.month_amount, 0)) AS max_payment_share
    FROM monthly_with_history AS mwh
    WHERE mwh.prev_months_count >= 1
      AND mwh.avg_prev_month_amount IS NOT NULL
      AND mwh.avg_prev_month_amount > 0
      AND mwh.month_amount > 3.0 * mwh.avg_prev_month_amount
      AND mwh.payment_count >= 3
      AND mwh.staff_count >= 2
      AND mwh.store_count >= 2
),
ranked AS (
    SELECT
        q.*,
        cc.country,
        cc.city,
        RANK() OVER (
            PARTITION BY cc.country, q.month_start
            ORDER BY q.month_amount DESC
        ) AS country_month_customer_rank
    FROM qualifying AS q
    JOIN country_city AS cc
      ON cc.customer_id = q.customer_id
)
SELECT
    strftime('%Y-%m', r.month_start) AS payment_month,
    c.h03 AS first_name,
    c.h04 AS last_name,
    r.country,
    r.city,
    r.payment_count,
    ROUND(r.month_amount, 2) AS total_amount,
    ROUND(r.max_payment, 2) AS max_payment,
    ROUND(r.max_payment_share, 4) AS max_payment_share,
    r.staff_count AS distinct_staff_count,
    r.store_count AS distinct_store_count,
    r.country_month_customer_rank
FROM ranked AS r
JOIN cus AS c
  ON c.h01 = r.customer_id
ORDER BY
    r.month_start,
    r.country,
    r.country_month_customer_rank,
    r.customer_id;