WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS customer_country,
        a.e05 AS city_id
    FROM cus AS c
    JOIN adr AS a
      ON a.e01 = c.h06
    JOIN cty AS ci
      ON ci.d01 = a.e05
    JOIN cnt
      ON cnt.c01 = ci.d03
),
payments_base AS (
    SELECT
        p.p02 AS customer_id,
        DATE(p.p06) AS payment_day,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p03 AS staff_id,
        s.o07 AS store_id
    FROM pay AS p
    JOIN stf AS s
      ON s.o01 = p.p03
),
daily_customer AS (
    SELECT
        pb.customer_id,
        cg.customer_name,
        cg.customer_country,
        pb.payment_day,
        COUNT(*) AS payment_count,
        SUM(pb.payment_amount) AS day_amount,
        COUNT(DISTINCT pb.staff_id) AS distinct_staff_count,
        COUNT(DISTINCT pb.store_id) AS distinct_store_count
    FROM payments_base AS pb
    JOIN customer_geo AS cg
      ON cg.customer_id = pb.customer_id
    GROUP BY
        pb.customer_id,
        cg.customer_name,
        cg.customer_country,
        pb.payment_day
),
daily_customer_with_history AS (
    SELECT
        dc.*,
        COALESCE((
            SELECT AVG(dc_prev.day_amount)
            FROM daily_customer AS dc_prev
            WHERE dc_prev.customer_id = dc.customer_id
              AND dc_prev.payment_day >= DATE(dc.payment_day, '-30 days')
              AND dc_prev.payment_day <  dc.payment_day
        ), 0.0) AS avg_prev_30d_day_amount
    FROM daily_customer AS dc
),
suspicious_days AS (
    SELECT
        dch.*,
        CASE
            WHEN dch.avg_prev_30d_day_amount > 0
                THEN dch.day_amount / dch.avg_prev_30d_day_amount
            ELSE NULL
        END AS exceed_ratio
    FROM daily_customer_with_history AS dch
    WHERE dch.avg_prev_30d_day_amount > 0
      AND dch.payment_count >= 3
      AND dch.day_amount >= 2.0 * dch.avg_prev_30d_day_amount
),
store_countries_by_day AS (
    SELECT
        pb.customer_id,
        DATE(pb.p6day) AS payment_day
    FROM (
        SELECT
            p.p02 AS customer_id,
            DATE(p.p06) AS payment_day,
            p.p03 AS staff_id,
            s.o07 AS store_id
        FROM pay AS p
        JOIN stf AS s
          ON s.o01 = p.p03
    ) AS pb
    JOIN sto AS st
      ON st.j01 = pb.store_id
    JOIN adr AS a
      ON a.e01 = st.j03
    JOIN cty AS ci
      ON ci.d01 = a.e05
    JOIN cnt
      ON cnt.c01 = ci.d03
    GROUP BY pb.customer_id, DATE(pb.payment_day)
),
day_staff_store_countries AS (
    SELECT
        pb.customer_id,
        pb.payment_day,
        cnt_shop.c02 AS store_country,
        COUNT(*) AS store_country_payment_count
    FROM payments_base AS pb
    JOIN sto AS st
      ON st.j01 = pb.store_id
    JOIN adr AS a
      ON a.e01 = st.j03
    JOIN cty AS ci
      ON ci.d01 = a.e05
    JOIN cnt AS cnt_shop
      ON cnt_shop.c01 = ci.d03
    GROUP BY
        pb.customer_id,
        pb.payment_day,
        cnt_shop.c02
),
day_has_offcountry_store_payment AS (
    SELECT
        d.customer_id,
        d.payment_day,
        MAX(
            CASE
                WHEN dsc.store_country <> d.customer_country THEN 1
                ELSE 0
            END
        ) AS has_store_country_diff_from_customer
    FROM suspicious_days AS d
    LEFT JOIN day_staff_store_countries AS dsc
      ON dsc.customer_id = d.customer_id
     AND dsc.payment_day = d.payment_day
    GROUP BY
        d.customer_id,
        d.payment_day
),
day_staff_store_summary AS (
    SELECT
        pb.customer_id,
        pb.payment_day,
        GROUP_CONCAT(DISTINCT st_shop.j01) AS involved_store_ids,
        COUNT(DISTINCT pb.staff_id) AS involved_staff_count,
        COUNT(DISTINCT pb.store_id) AS involved_store_count,
        GROUP_CONCAT(DISTINCT cnt_shop.c02) AS involved_store_countries,
        SUM(CASE WHEN cnt_shop.c02 <> cg.customer_country THEN 1 ELSE 0 END) AS offcountry_payment_count,
        SUM(CASE WHEN cnt_shop.c02 = cg.customer_country THEN 1 ELSE 0 END) AS samecountry_payment_count
    FROM payments_base AS pb
    JOIN stf AS s
      ON s.o01 = pb.staff_id
    JOIN sto AS st_shop
      ON st_shop.j01 = pb.store_id
    JOIN adr AS a
      ON a.e01 = st_shop.j03
    JOIN cty AS ci
      ON ci.d01 = a.e05
    JOIN cnt AS cnt_shop
      ON cnt_shop.c01 = ci.d03
    JOIN customer_geo AS cg
      ON cg.customer_id = pb.customer_id
    GROUP BY
        pb.customer_id,
        pb.payment_day
),
ranked_suspicious AS (
    SELECT
        sd.*,
        RANK() OVER (
            PARTITION BY sd.customer_country
            ORDER BY sd.exceed_ratio DESC, sd.day_amount DESC, sd.payment_day
        ) AS suspicion_rank_in_country
    FROM suspicious_days AS sd
)
SELECT
    rs.customer_id,
    rs.customer_name,
    rs.payment_day AS payment_date,
    rs.customer_country,
    rs.payment_count,
    ROUND(rs.day_amount, 2) AS day_payment_amount,
    ROUND(rs.avg_prev_30d_day_amount, 2) AS avg_prev_30d_day_amount,
    ROUND(rs.exceed_ratio, 3) AS exceed_ratio,
    dss.involved_staff_count AS involved_staff_count,
    dss.involved_store_count AS involved_store_count,
    dss.involved_store_countries AS store_countries_involved,
    dss.involved_store_ids AS store_ids_involved,
    MAX(CASE WHEN ds_off.has_store_country_diff_from_customer = 1 THEN 1 ELSE 0 END) AS has_offcountry_store_payment,
    rs.suspicion_rank_in_country
FROM ranked_suspicious AS rs
JOIN day_staff_store_summary AS dss
  ON dss.customer_id = rs.customer_id
 AND dss.payment_day = rs.payment_day
LEFT JOIN day_has_offcountry_store_payment AS ds_off
  ON ds_off.customer_id = rs.customer_id
 AND ds_off.payment_day = rs.payment_day
GROUP BY
    rs.customer_id,
    rs.customer_name,
    rs.payment_day,
    rs.customer_country,
    rs.payment_count,
    rs.day_amount,
    rs.avg_prev_30d_day_amount,
    rs.exceed_ratio,
    dss.involved_staff_count,
    dss.involved_store_count,
    dss.involved_store_countries,
    dss.involved_store_ids,
    ds_off.has_store_country_diff_from_customer,
    rs.suspicion_rank_in_country
ORDER BY
    rs.customer_country,
    rs.suspicion_rank_in_country,
    rs.payment_day,
    rs.customer_id;