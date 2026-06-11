WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h02 AS home_store_id,
        cnt.c01 AS country_id,
        cnt.c02 AS country_name
    FROM cus AS c
    JOIN sto AS s_home ON s_home.j01 = c.h02
    JOIN adr AS a_home ON a_home.e01 = s_home.j03
    JOIN cty AS ci_home ON ci_home.d01 = a_home.e05
    JOIN cnt AS cnt ON cnt.c01 = ci_home.d03
),
monthly_payments AS (
    SELECT
        p.p02 AS customer_id,
        strftime('%Y-%m', p.p06) AS month_ym,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS payment_sum,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        SUM(CASE WHEN p.p04 IS NULL THEN 1 ELSE 0 END) AS dummy_payments_cnt,
        SUM(CASE
                WHEN p.p04 IS NOT NULL AND p.p03 IS NOT NULL AND s_staff.j01 <> cg.home_store_id
                THEN CAST(1 AS REAL)
                ELSE CAST(0 AS REAL)
            END) AS off_home_staff_payment_count,
        SUM(CASE
                WHEN p.p04 IS NOT NULL AND s_staff.j01 <> cg.home_store_id
                THEN CAST(p.p05 AS REAL)
                ELSE CAST(0 AS REAL)
            END) AS off_home_staff_payment_sum
    FROM pay AS p
    JOIN customer_geo AS cg ON cg.customer_id = p.p02
    JOIN stf AS s_staff ON s_staff.o01 = p.p03
    GROUP BY
        p.p02,
        strftime('%Y-%m', p.p06)
),
monthly_with_history AS (
    SELECT
        mp.*,
        AVG(mp.payment_sum) OVER (
            PARTITION BY mp.customer_id
            ORDER BY mp.month_ym
            ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
        ) AS personal_avg_prev_2_months
    FROM monthly_payments AS mp
),
country_month_ranked AS (
    SELECT
        month_ym,
        country_id,
        customer_id,
        payment_sum,
        payment_count,
        distinct_staff_count,
        personal_avg_prev_2_months,
        off_home_staff_payment_count,
        off_home_staff_payment_sum,
        ROW_NUMBER() OVER (
            PARTITION BY country_id, month_ym
            ORDER BY payment_sum
        ) AS rn_asc,
        COUNT(*) OVER (PARTITION BY country_id, month_ym) AS cnt_in_country_month
    FROM (
        SELECT
            mwh.*,
            cg.country_id
        FROM monthly_with_history AS mwh
        JOIN customer_geo AS cg
          ON cg.customer_id = mwh.customer_id
    ) AS x
),
country_p95 AS (
    SELECT
        month_ym,
        country_id,
        MAX(CASE
                WHEN rn_asc = CAST(((95.0 * cnt_in_country_month) + 1) / 100 AS INTEGER)
                THEN payment_sum
            END) AS country_p95_payment_sum
    FROM country_month_ranked
    GROUP BY month_ym, country_id
),
qualified AS (
    SELECT
        mwh.month_ym,
        mwh.customer_id,
        cg.country_name,
        mwh.payment_count,
        mwh.payment_sum,
        mwh.personal_avg_prev_2_months,
        cp.country_p95_payment_sum,
        mwh.off_home_staff_payment_count,
        mwh.distinct_staff_count,
        (mwh.off_home_staff_payment_count * 1.0 / NULLIF(mwh.payment_count, 0)) AS off_home_staff_payment_share,
        RANK() OVER (
            PARTITION BY cg.country_id, mwh.month_ym
            ORDER BY mwh.payment_sum DESC
        ) AS customer_rank_in_country_month
    FROM monthly_with_history AS mwh
    JOIN customer_geo AS cg
      ON cg.customer_id = mwh.customer_id
    JOIN country_p95 AS cp
      ON cp.month_ym = mwh.month_ym
     AND cp.country_id = cg.country_id
    WHERE
        mwh.personal_avg_prev_2_months IS NOT NULL
        AND mwh.personal_avg_prev_2_months > 0
        AND mwh.payment_sum >= 3.0 * mwh.personal_avg_prev_2_months
        AND mwh.payment_sum > cp.country_p95_payment_sum
)
SELECT
    month_ym AS month,
    customer_id,
    country_name,
    payment_count,
    ROUND(payment_sum, 2) AS payment_sum,
    ROUND(personal_avg_prev_2_months, 2) AS personal_avg_prev_2_months,
    ROUND(cp.country_p95_payment_sum, 2) AS country_p95_payment_sum,
    ROUND(off_home_staff_payment_share, 4) AS off_home_staff_payment_share,
    distinct_staff_count AS distinct_staff_accepting_payment_count,
    customer_rank_in_country_month
FROM (
    SELECT q.*, cg2.country_id, q.country_name, cp.country_p95_payment_sum
    FROM qualified AS q
    JOIN customer_geo AS cg2 ON cg2.customer_id = q.customer_id
    JOIN country_p95 AS cp
      ON cp.month_ym = q.month_ym
     AND cp.country_id = cg2.country_id
) AS out
ORDER BY
    month,
    country_name,
    customer_rank_in_country_month,
    payment_sum DESC,
    customer_id;