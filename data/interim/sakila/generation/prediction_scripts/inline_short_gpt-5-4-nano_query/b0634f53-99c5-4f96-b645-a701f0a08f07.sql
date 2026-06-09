WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        co.c02 AS customer_country,
        ci.d02 AS customer_city
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
        SUM(CAST(p.p05 AS REAL)) AS day_amount,
        COUNT(DISTINCT p.p03) AS staff_count,
        COUNT(DISTINCT s.o07) AS store_count,
        COUNT(DISTINCT co_store.c02) AS store_countries_count,
        SUM(
            CASE WHEN co_store.c01 <> cgeo_customer.countries_cid THEN 1 ELSE 0 END
        ) AS other_country_payment_count
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    JOIN sto AS sto ON sto.j01 = s.o07
    JOIN adr AS adr_store ON adr_store.e01 = sto.j03
    JOIN cty AS cty_store ON cty_store.d01 = adr_store.e05
    JOIN cnt AS co_store ON co_store.c01 = cty_store.d03
    JOIN (
        SELECT
            h01 AS customer_id,
            c.h01 AS customer_id2,
            c.h03 || ' ' || c.h04 AS customer_name2,
            co.c01 AS countries_cid
        FROM cus c
        JOIN adr a ON a.e01 = c.h06
        JOIN cty ci ON ci.d01 = a.e05
        JOIN cnt co ON co.c01 = ci.d03
    ) AS cgeo_customer ON cgeo_customer.customer_id = p.p02
    JOIN customer_geo AS cg ON cg.customer_id = p.p02
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 <  '2006-01-01'
    GROUP BY
        p.p02,
        date(p.p06)
),
daily_customer_with_avg AS (
    SELECT
        dcp.*,
        COALESCE((
            SELECT AVG(dcp_prev.day_amount)
            FROM daily_customer_pay AS dcp_prev
            WHERE dcp_prev.customer_id = dcp.customer_id
              AND dcp_prev.payment_date >= date(dcp.payment_date, '-30 day')
              AND dcp_prev.payment_date <  dcp.payment_date
        ), 0.0) AS avg_prev_30d_amount
    FROM daily_customer_pay AS dcp
),
flagged_days AS (
    SELECT
        dcwa.*,
        dcwa.day_amount / NULLIF(dcwa.avg_prev_30d_amount, 0) AS exceed_ratio
    FROM daily_customer_with_avg AS dcwa
    WHERE dcwa.payment_count >= 3
      AND dcwa.avg_prev_30d_amount > 0
      AND dcwa.day_amount >= 2.0 * dcwa.avg_prev_30d_amount
      AND dcwa.other_country_payment_count >= 1
),
store_countries_per_day AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        GROUP_CONCAT(DISTINCT co_store.c02) AS store_countries_list
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
    JOIN sto AS sto ON sto.j01 = s.o07
    JOIN adr AS adr_store ON adr_store.e01 = sto.j03
    JOIN cty AS cty_store ON cty_store.d01 = adr_store.e05
    JOIN cnt AS co_store ON co_store.c01 = cty_store.d03
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 <  '2006-01-01'
    GROUP BY
        p.p02,
        date(p.p06)
)
SELECT
    f.customer_id,
    cg.customer_name,
    cg.customer_country AS customer_country,
    f.payment_date,
    f.payment_count,
    ROUND(f.day_amount, 2) AS day_amount,
    ROUND(f.avg_prev_30d_amount, 2) AS avg_prev_30d_amount,
    f.staff_count AS staff_count,
    f.store_count AS store_count,
    scpd.store_countries_list AS store_countries,
    RANK() OVER (
        PARTITION BY cg.customer_country
        ORDER BY (f.day_amount - f.avg_prev_30d_amount) DESC, f.day_amount DESC
    ) AS suspicious_rank_within_customer_country
FROM flagged_days AS f
JOIN customer_geo AS cg
    ON cg.customer_id = f.customer_id
JOIN store_countries_per_day AS scpd
    ON scpd.customer_id = f.customer_id
   AND scpd.payment_date = f.payment_date
ORDER BY
    cg.customer_country,
    suspicious_rank_within_customer_country,
    f.payment_date,
    f.customer_id;