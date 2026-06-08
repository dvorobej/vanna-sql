WITH payment_details AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_date,
        CAST(p.p05 AS REAL) AS amount,
        p.p03 AS staff_id,
        COALESCE(inv.n03, stf.o07) AS store_id,
        CASE
            WHEN flm.i11 IN ('R', 'NC-17') THEN 1
            ELSE 0
        END AS is_r_or_nc17
    FROM pay AS p
    JOIN stf AS stf
        ON stf.o01 = p.p03
    LEFT JOIN ren AS ren
        ON ren.q01 = p.p04
    LEFT JOIN inv AS inv
        ON inv.n01 = ren.q03
    LEFT JOIN flm AS flm
        ON flm.i01 = inv.n02
),
customer_day AS (
    SELECT
        cus.h01 AS customer_id,
        cus.h03 || ' ' || cus.h04 AS customer_name,
        cty.d02 AS city_name,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name,
        pd.payment_date,
        COUNT(*) AS payment_count,
        ROUND(SUM(pd.amount), 2) AS total_amount,
        ROUND(MAX(pd.amount), 2) AS max_payment,
        ROUND(SUM(pd.is_r_or_nc17) * 1.0 / COUNT(*), 4) AS r_or_nc17_payment_share,
        COUNT(DISTINCT pd.staff_id) AS distinct_staff_count,
        COUNT(DISTINCT pd.store_id) AS distinct_store_count
    FROM payment_details AS pd
    JOIN cus AS cus
        ON cus.h01 = pd.customer_id
    JOIN adr AS adr
        ON adr.e01 = cus.h06
    JOIN cty AS cty
        ON cty.d01 = adr.e05
    JOIN cnt AS cnt
        ON cnt.c01 = cty.d03
    GROUP BY
        cus.h01,
        cus.h03,
        cus.h04,
        cty.d02,
        cnt.c01,
        cnt.c02,
        pd.payment_date
),
customer_day_with_baseline AS (
    SELECT
        cd.*,
        (
            SELECT SUM(cd_prev.total_amount) / 30.0
            FROM customer_day AS cd_prev
            WHERE cd_prev.customer_id = cd.customer_id
              AND cd_prev.payment_date >= DATE(cd.payment_date, '-30 day')
              AND cd_prev.payment_date < cd.payment_date
        ) AS avg_daily_amount_prev_30_days
    FROM customer_day AS cd
),
ranked_days AS (
    SELECT
        *,
        RANK() OVER (
            PARTITION BY country_id
            ORDER BY total_amount DESC
        ) AS country_amount_rank
    FROM customer_day_with_baseline
)
SELECT
    customer_id,
    customer_name,
    city_name,
    country_name,
    payment_date,
    payment_count,
    total_amount,
    max_payment,
    r_or_nc17_payment_share,
    country_amount_rank
FROM ranked_days
WHERE avg_daily_amount_prev_30_days IS NOT NULL
  AND total_amount >= 3.0 * avg_daily_amount_prev_30_days
  AND payment_count >= 3
  AND (
      distinct_staff_count > 1
      OR distinct_store_count > 1
  )
ORDER BY
    country_name,
    country_amount_rank,
    payment_date,
    customer_id;