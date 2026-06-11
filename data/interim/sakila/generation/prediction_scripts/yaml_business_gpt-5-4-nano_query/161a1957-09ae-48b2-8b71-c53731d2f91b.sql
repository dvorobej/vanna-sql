WITH pay_daily AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS pay_date,
        COUNT(*) AS payment_count,
        SUM(CAST(p.p05 AS REAL)) AS day_sum
    FROM pay AS p
    GROUP BY p.p02, date(p.p06)
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        cty.d02 AS city,
        cnt.c01 AS country_id,
        cnt.c02 AS country
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty ON cty.d01 = a.e05
    JOIN cnt ON cnt.c01 = cty.d03
),
customer_staff_store AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS pay_date,
        GROUP_CONCAT(DISTINCT (st.o02 || ' ' || st.o03)) AS staff_list,
        GROUP_CONCAT(DISTINCT sto.j01) AS store_list
    FROM pay AS p
    JOIN stf AS st ON st.o01 = p.p03
    LEFT JOIN sto ON sto.j01 = st.o07
    GROUP BY p.p02, date(p.p06)
),
personal_daily_avg AS (
    SELECT
        cd.customer_id,
        cd.pay_date,
        cd.payment_count,
        cd.day_sum,
        (
            SELECT AVG(dpa.day_sum)
            FROM pay_daily AS dpa
            WHERE dpa.customer_id = cd.customer_id
              AND dpa.pay_date >= date(cd.pay_date, '-30 days')
              AND dpa.pay_date < cd.pay_date
        ) AS personal_avg_prev_30d
    FROM pay_daily AS cd
),
country_daily_sums AS (
    SELECT
        cg.country_id,
        pd.pay_date,
        pd.day_sum
    FROM pay_daily AS pd
    JOIN customer_geo AS cg ON cg.customer_id = pd.customer_id
),
country_daily_rank AS (
    SELECT
        country_id,
        pay_date,
        day_sum,
        ROW_NUMBER() OVER (
            PARTITION BY country_id, pay_date
            ORDER BY day_sum
        ) AS rn_asc,
        COUNT(*) OVER (
            PARTITION BY country_id, pay_date
        ) AS cnt_in_partition
    FROM country_daily_sums
),
country_p95 AS (
    SELECT
        country_id,
        pay_date,
        MIN(day_sum) AS p95_daily_sum
    FROM country_daily_rank
    WHERE rn_asc >= CAST((95 * cnt_in_partition + 99) / 100 AS INTEGER)
    GROUP BY country_id, pay_date
),
candidates AS (
    SELECT
        pda.customer_id,
        cg.country_id,
        cg.country,
        cg.city,
        pda.pay_date,
        pda.payment_count,
        pda.day_sum,
        pda.personal_avg_prev_30d,
        (pda.day_sum - pda.personal_avg_prev_30d) AS deviation_from_personal_avg,
        cp.p95_daily_sum
    FROM personal_daily_avg AS pda
    JOIN customer_geo AS cg ON cg.customer_id = pda.customer_id
    JOIN country_p95 AS cp
      ON cp.country_id = cg.country_id
     AND cp.pay_date = pda.pay_date
    WHERE pda.payment_count >= 3
      AND pda.personal_avg_prev_30d IS NOT NULL
      AND pda.personal_avg_prev_30d > 0
      AND pda.day_sum > 2.0 * pda.personal_avg_prev_30d
      AND pda.day_sum > cp.p95_daily_sum
),
staff_counts AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS pay_date,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT p.p04) AS rental_refs_count
    FROM pay AS p
    GROUP BY p.p02, date(p.p06)
),
store_counts AS (
    SELECT
        stf.o01 AS staff_id,
        stf.o07 AS store_id
    FROM stf
),
final_cases AS (
    SELECT
        c.*,
        sc.staff_count,
        csp.staff_list
    FROM candidates AS c
    JOIN staff_counts AS sc
      ON sc.customer_id = c.customer_id
     AND sc.pay_date = c.pay_date
    JOIN customer_staff_store AS csp
      ON csp.customer_id = c.customer_id
     AND csp.pay_date = c.pay_date
    WHERE sc.staff_count >= 2
)
SELECT
    fc.customer_id,
    fc.country,
    fc.city,
    fc.pay_date AS spike_date,
    fc.payment_count,
    ROUND(fc.day_sum, 2) AS day_sum,
    fc.staff_list AS staff_list,
    ROUND(fc.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
    DENSE_RANK() OVER (
        PARTITION BY fc.country_id
        ORDER BY fc.deviation_from_personal_avg DESC
    ) AS country_suspicion_rank
FROM final_cases AS fc
ORDER BY
    fc.country,
    country_suspicion_rank,
    fc.pay_date,
    fc.customer_id;