WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        co.c02 AS customer_country_name,
        ci.d02 AS customer_city_name,
        adr.e01 AS address_id
    FROM cus AS c
    JOIN adr ON adr.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = adr.e05
    JOIN cnt AS co ON co.c01 = ci.d03
),
payments_base AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_day,
        p.p03 AS staff_id,
        s.o07 AS store_id,
        p.p05 AS payment_amount
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
),
daily_rollup AS (
    SELECT
        pb.customer_id,
        pb.payment_day,
        COUNT(*) AS payment_count,
        SUM(pb.payment_amount) AS day_amount,
        COUNT(DISTINCT pb.staff_id) AS distinct_staff_count,
        COUNT(DISTINCT pb.store_id) AS distinct_store_count
    FROM payments_base AS pb
    GROUP BY
        pb.customer_id,
        pb.payment_day
),
off_country_store_days AS (
    SELECT
        pb.customer_id,
        pb.payment_day,
        COUNT(DISTINCT CASE WHEN mc.store_country_name <> cg.customer_country_name THEN pb.store_id END) AS off_country_store_count,
        COUNT(DISTINCT CASE WHEN mc.store_country_name <> cg.customer_country_name THEN pb.staff_id END) AS off_country_staff_count,
        MAX(CASE WHEN mc.store_country_name <> cg.customer_country_name THEN 1 ELSE 0 END) AS has_off_country_store
    FROM payments_base AS pb
    JOIN customer_geo AS cg
        ON cg.customer_id = pb.customer_id
    JOIN sto AS st
        ON st.j01 = pb.store_id
    JOIN adr AS sa
        ON sa.e01 = st.j03
    JOIN cty AS sci
        ON sci.d01 = sa.e05
    JOIN cnt AS mc
        ON mc.c01 = sci.d03
    GROUP BY
        pb.customer_id,
        pb.payment_day
),
scored AS (
    SELECT
        dr.*,
        cg.customer_country_name,
        (
            SELECT AVG(dr2.day_amount)
            FROM daily_rollup AS dr2
            WHERE dr2.customer_id = dr.customer_id
              AND dr2.payment_day >= date(dr.payment_day, '-30 days')
              AND dr2.payment_day < dr.payment_day
        ) AS avg_day_amount_prev_30d
    FROM daily_rollup AS dr
    JOIN customer_geo AS cg
        ON cg.customer_id = dr.customer_id
)
SELECT
    s.customer_id,
    s.payment_day AS suspicious_date,
    s.customer_country_name AS customer_country,
    s.payment_count,
    ROUND(s.day_amount, 2) AS day_payment_sum,
    ROUND(s.avg_day_amount_prev_30d, 2) AS avg_day_amount_prev_30_days,
    s.day_amount / NULLIF(s.avg_day_amount_prev_30d, 0) AS exceed_ratio,
    s.distinct_staff_count AS staff_count_distinct,
    s.distinct_store_count AS store_count_distinct,
    (SELECT COUNT(DISTINCT pbb.store_id)
     FROM payments_base pbb
     JOIN sto st ON st.j01 = pbb.store_id
     JOIN adr sa ON sa.e01 = st.j03
     JOIN cty sci ON sci.d01 = sa.e05
     JOIN cnt mc ON mc.c01 = sci.d03
     WHERE pbb.customer_id = s.customer_id
       AND pbb.payment_day = s.payment_day
       AND mc.c01 IN (
           SELECT cci.c01
           FROM cnt cci
       )
    ) AS stores_total_distinct,
    DENSE_RANK() OVER (
        PARTITION BY s.customer_id
        ORDER BY (s.day_amount / NULLIF(s.avg_day_amount_prev_30d, 0)) DESC, s.day_amount DESC, s.payment_day DESC
    ) AS suspicious_rank_within_customer
FROM scored AS s
JOIN off_country_store_days AS oc
    ON oc.customer_id = s.customer_id
   AND oc.payment_day = s.payment_day
WHERE s.avg_day_amount_prev_30d IS NOT NULL
  AND s.avg_day_amount_prev_30d > 0
  AND YEAR(s.payment_day) = 2005
  AND s.payment_count >= 3
  AND s.day_amount >= 2.0 * s.avg_day_amount_prev_30d
  AND oc.has_off_country_store = 1
ORDER BY
  s.customer_country_name,
  suspicious_rank_within_customer,
  s.payment_day,
  s.customer_id;