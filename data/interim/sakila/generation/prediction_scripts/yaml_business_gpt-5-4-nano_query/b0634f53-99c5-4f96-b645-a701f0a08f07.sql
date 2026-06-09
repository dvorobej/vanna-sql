WITH payments_2005 AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        p.p04 AS rental_id,
        CAST(p.p05 AS REAL) AS payment_amount,
        p.p06 AS payment_dt,
        date(p.p06) AS payment_day,
        strftime('%Y', p.p06) AS payment_year
    FROM pay AS p
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 <  '2006-01-01'
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        co.c02 AS customer_country,
        ci.d02 AS customer_city
    FROM cus AS c
    JOIN adr AS a  ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
),
daily_customer AS (
    SELECT
        p.customer_id,
        cg.customer_country,
        p.payment_day,
        SUM(p.payment_amount) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.staff_id) AS distinct_staff_count
    FROM payments_2005 AS p
    JOIN customer_geo AS cg ON cg.customer_id = p.customer_id
    GROUP BY
        p.customer_id,
        cg.customer_country,
        p.payment_day
),
daily_customer_with_prev AS (
    SELECT
        dc.*,
        (
            SELECT AVG(dc_prev.day_amount)
            FROM daily_customer AS dc_prev
            WHERE dc_prev.customer_id = dc.customer_id
              AND dc_prev.payment_day >= date(dc.payment_day, '-30 days')
              AND dc_prev.payment_day <  dc.payment_day
        ) AS avg_day_amount_prev_30d
    FROM daily_customer AS dc
),
staff_store_country AS (
    SELECT
        st.o01 AS staff_id,
        sto.j01 AS store_id,
        co.c02 AS store_country
    FROM stf AS st
    JOIN sto ON sto.j02 = st.o01
    JOIN adr a ON a.e01 = sto.j03
    JOIN cty ci ON ci.d01 = a.e05
    JOIN cnt co ON co.c01 = ci.d03
),
daily_enriched AS (
    SELECT
        p.customer_id,
        cg.customer_country,
        p.payment_day,
        SUM(p.payment_amount) AS day_amount,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT p.staff_id) AS distinct_staff_count,
        COUNT(DISTINCT ssc.store_id) AS distinct_store_count,
        GROUP_CONCAT(DISTINCT ssc.store_country) AS store_countries
    FROM payments_2005 AS p
    JOIN customer_geo AS cg
        ON cg.customer_id = p.customer_id
    LEFT JOIN staff_store_country AS ssc
        ON ssc.staff_id = p.staff_id
    GROUP BY
        p.customer_id,
        cg.customer_country,
        p.payment_day
),
suspicious_days AS (
    SELECT
        de.*,
        (
            SELECT AVG(de_prev.day_amount)
            FROM daily_enriched AS de_prev
            WHERE de_prev.customer_id = de.customer_id
              AND de_prev.payment_day >= date(de.payment_day, '-30 days')
              AND de_prev.payment_day <  de.payment_day
        ) AS avg_day_amount_prev_30d
    FROM daily_enriched AS de
),
final_scored AS (
    SELECT
        sd.customer_id,
        cg.customer_city,
        sd.customer_country,
        sd.payment_day,
        sd.payment_count,
        sd.day_amount,
        sd.avg_day_amount_prev_30d,
        sd.distinct_staff_count,
        sd.distinct_store_count,
        sd.store_countries,
        RANK() OVER (
            PARTITION BY sd.customer_country
            ORDER BY (sd.day_amount / NULLIF(sd.avg_day_amount_prev_30d, 0)) DESC, sd.day_amount DESC
        ) AS suspicion_rank_in_country
    FROM suspicious_days AS sd
    JOIN customer_geo AS cg
      ON cg.customer_id = sd.customer_id
    WHERE sd.avg_day_amount_prev_30d IS NOT NULL
      AND sd.payment_count >= 3
      AND sd.day_amount >= 2.0 * sd.avg_day_amount_prev_30d
      AND EXISTS (
          SELECT 1
          FROM payments_2005 p2
          LEFT JOIN staff_store_country ssc2
            ON ssc2.staff_id = p2.staff_id
          WHERE p2.customer_id = sd.customer_id
            AND p2.payment_day = sd.payment_day
            AND ssc2.store_country IS NOT NULL
            AND ssc2.store_country <> sd.customer_country
      )
)
SELECT
    fs.customer_id,
    fs.customer_city,
    fs.customer_country,
    fs.payment_day AS payment_date,
    fs.payment_count,
    ROUND(fs.day_amount, 2) AS day_payment_amount,
    ROUND(fs.avg_day_amount_prev_30d, 2) AS avg_day_amount_prev_30d,
    fs.distinct_staff_count,
    fs.distinct_store_count,
    fs.store_countries,
    fs.suspicion_rank_in_country
FROM final_scored AS fs
ORDER BY
    fs.customer_country,
    fs.suspicion_rank_in_country,
    fs.day_amount DESC,
    fs.customer_id,
    fs.payment_day;