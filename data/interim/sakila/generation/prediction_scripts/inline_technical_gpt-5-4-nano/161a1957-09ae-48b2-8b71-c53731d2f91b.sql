WITH pay_enriched AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p03 AS staff_id,
        s.o07 AS staff_store_id,
        cus.h06 AS customer_address_id,
        adr.e05 AS customer_city_id,
        cty.d03 AS customer_country_id,
        cty.d02 AS customer_city,
        cnt.c02 AS customer_country
    FROM pay AS p
    JOIN cus
        ON cus.h01 = p.p02
    JOIN stf AS s
        ON s.o01 = p.p03
    JOIN adr
        ON adr.e01 = cus.h06
    JOIN cty
        ON cty.d01 = adr.e05
    JOIN cnt
        ON cnt.c01 = cty.d03
),
daily_agg AS (
    SELECT
        customer_id,
        customer_country_id,
        customer_country,
        customer_city,
        payment_date,
        COUNT(*) AS daily_payment_count,
        SUM(payment_amount) AS daily_amount,
        COUNT(DISTINCT staff_id) AS staff_count,
        COUNT(DISTINCT staff_store_id) AS store_count,
        GROUP_CONCAT(DISTINCT staff_id) AS involved_staff_ids
    FROM pay_enriched
    GROUP BY
        customer_id,
        customer_country_id,
        customer_country,
        customer_city,
        payment_date
),
daily_with_hist AS (
    SELECT
        da.*,
        (
            SELECT AVG(da_prev.daily_amount)
            FROM daily_agg AS da_prev
            WHERE da_prev.customer_id = da.customer_id
              AND da_prev.payment_date >= date(da.payment_date, '-30 days')
              AND da_prev.payment_date < da.payment_date
        ) AS avg_prev_30d
    FROM daily_agg AS da
),
country_p95 AS (
    SELECT
        customer_country_id,
        payment_date,
        daily_amount,
        ROW_NUMBER() OVER (
            PARTITION BY customer_country_id, payment_date
            ORDER BY daily_amount
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY customer_country_id, payment_date
        ) AS cnt_days
    FROM daily_agg
),
country_p95_value AS (
    SELECT
        customer_country_id,
        payment_date,
        daily_amount AS country_p95_daily_amount
    FROM country_p95
    WHERE rn >= CAST((95 * cnt_days + 99) / 100 AS INTEGER)
),
flagged_days AS (
    SELECT
        dwh.*,
        (dwh.daily_amount - dwh.avg_prev_30d) AS deviation_from_personal_avg,
        cp.country_p95_daily_amount,
        dwh.daily_amount / NULLIF(cp.country_p95_daily_amount, 0) AS ratio_to_country_p95
    FROM daily_with_hist AS dwh
    JOIN country_p95_value AS cp
      ON cp.customer_country_id = dwh.customer_country_id
     AND cp.payment_date = dwh.payment_date
    WHERE dwh.daily_payment_count >= 3
      AND (dwh.staff_count >= 2 OR dwh.store_count >= 2)
      AND dwh.avg_prev_30d IS NOT NULL
      AND cp.country_p95_daily_amount IS NOT NULL
      AND dwh.daily_amount >= 0
),
ranked AS (
    SELECT
        fd.*,
        RANK() OVER (
            PARTITION BY fd.customer_country_id
            ORDER BY fd.ratio_to_country_p95 DESC, fd.daily_amount DESC
        ) AS daily_amount_rank_in_country
    FROM flagged_days AS fd
)
SELECT
    r.customer_id AS h01,
    r.customer_country AS cnt_c02,
    r.customer_city AS cty_d02,
    r.payment_date AS p06_day,
    r.daily_payment_count AS daily_payment_count,
    ROUND(r.daily_amount, 2) AS daily_amount,
    r.involved_staff_ids AS staff_o01_list,
    ROUND(r.avg_prev_30d, 2) AS avg_prev_30d_daily_amount,
    ROUND(r.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
    r.daily_amount_rank_in_country
FROM ranked AS r
ORDER BY
    r.customer_country,
    r.daily_amount_rank_in_country,
    r.daily_amount DESC,
    r.customer_id,
    r.payment_date;