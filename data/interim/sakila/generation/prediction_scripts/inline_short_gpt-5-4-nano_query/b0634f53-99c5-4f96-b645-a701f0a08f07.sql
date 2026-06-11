WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        cnt.c02 AS customer_country_name,
        ci.d02 AS customer_city_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt ON cnt.c01 = ci.d03
),
payment_staff_store AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p03 AS staff_id,
        st.o07 AS staff_store_id,
        sgeo.store_country_name
    FROM pay AS p
    JOIN stf AS st ON st.o01 = p.p03
    JOIN (
        SELECT
            st2.o01 AS staff_id,
            cnt2.c02 AS store_country_name
        FROM stf AS st2
        JOIN adr AS a2 ON a2.e01 = st2.o04
        JOIN cty AS ci2 ON ci2.d01 = a2.e05
        JOIN cnt AS cnt2 ON cnt2.c01 = ci2.d03
    ) AS sgeo
      ON sgeo.staff_id = st.o01
),
daily_agg AS (
    SELECT
        ps.customer_id,
        ps.payment_date,
        COUNT(*) AS day_payment_count,
        SUM(ps.payment_amount) AS day_payment_sum,
        COUNT(DISTINCT ps.staff_id) AS staff_count,
        COUNT(DISTINCT ps.staff_store_id) AS store_count,
        MAX(CASE WHEN ps.store_country_name <> cg.customer_country_name THEN 1 ELSE 0 END) AS has_other_country_store_payment,
        GROUP_CONCAT(DISTINCT ps.store_country_name) AS store_countries_list
    FROM payment_staff_store AS ps
    JOIN customer_geo AS cg
      ON cg.customer_id = ps.customer_id
    GROUP BY
        ps.customer_id,
        ps.payment_date
),
daily_with_hist AS (
    SELECT
        da.*,
        (
            SELECT AVG(da2.day_payment_sum)
            FROM daily_agg AS da2
            WHERE da2.customer_id = da.customer_id
              AND da2.payment_date >= date(da.payment_date, '-30 day')
              AND da2.payment_date <  da.payment_date
        ) AS avg_prev_30d_sum
    FROM daily_agg AS da
),
flagged AS (
    SELECT
        dwh.*,
        (dwh.day_payment_sum / NULLIF(dwh.avg_prev_30d_sum, 0)) AS sum_ratio,
        RANK() OVER (
            PARTITION BY dwh.customer_id, dwh.has_other_country_store_payment
            ORDER BY (dwh.day_payment_sum / NULLIF(dwh.avg_prev_30d_sum, 0)) DESC, dwh.day_payment_sum DESC, dwh.payment_date
        ) AS suspicious_rank_dummy
    FROM daily_with_hist AS dwh
    WHERE dwh.avg_prev_30d_sum IS NOT NULL
      AND dwh.avg_prev_30d_sum > 0
      AND dwh.day_payment_count >= 3
      AND dwh.day_payment_sum >= 2.0 * dwh.avg_prev_30d_sum
      AND dwh.has_other_country_store_payment = 1
),
final_ranked AS (
    SELECT
        f.*,
        RANK() OVER (
            PARTITION BY cg.customer_country_name
            ORDER BY f.day_payment_sum / NULLIF(f.avg_prev_30d_sum, 0) DESC, f.day_payment_sum DESC, f.payment_date
        ) AS suspicious_rank_in_country
    FROM flagged f
    JOIN customer_geo cg
      ON cg.customer_id = f.customer_id
)
SELECT
    c.h01 AS customer_id,
    c.h03 || ' ' || c.h04 AS customer_name,
    cg.customer_country_name AS customer_country,
    f.payment_date AS suspicious_date,
    f.day_payment_count AS payment_count,
    ROUND(f.day_payment_sum, 2) AS day_payment_sum,
    ROUND(f.avg_prev_30d_sum, 2) AS avg_prev_30d_day_sum,
    f.staff_count AS distinct_staff_count,
    f.store_count AS distinct_store_count,
    f.store_countries_list AS store_countries,
    f.suspicious_rank_in_country AS suspicious_rank_in_customer_country
FROM final_ranked AS f
JOIN cus AS c ON c.h01 = f.customer_id
JOIN customer_geo AS cg ON cg.customer_id = f.customer_id
ORDER BY
    cg.customer_country_name,
    f.suspicious_rank_in_country,
    f.payment_date,
    f.customer_id;