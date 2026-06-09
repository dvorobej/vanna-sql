WITH customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 || ' ' || c.h04 AS customer_name,
        cnt.c02 AS customer_country
    FROM cus AS c
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ci
        ON ci.d01 = a.e05
    JOIN cnt AS cnt
        ON cnt.c01 = ci.d03
),
payments_day AS (
    SELECT
        p.p02 AS customer_id,
        date(p.p06) AS payment_date,
        cg.customer_country,
        COUNT(*) AS payment_count,
        SUM(p.p05) AS day_payment_amount,
        COUNT(DISTINCT p.p03) AS distinct_staff_count,
        COUNT(DISTINCT s.o07) AS distinct_store_count,
        group_concat(DISTINCT (scnt.c02)) AS store_countries,
        group_concat(DISTINCT (s.o07)) AS store_ids,
        group_concat(DISTINCT (st.d02 || ',' || st.d03)) AS stores_context
    FROM pay AS p
    JOIN customer_geo AS cg
        ON cg.customer_id = p.p02
    JOIN stf AS s
        ON s.o01 = p.p03
    LEFT JOIN sto AS store
        ON store.j01 = s.o07
    LEFT JOIN adr AS sa
        ON sa.e01 = store.j06
    LEFT JOIN cty AS scity
        ON scity.d01 = sa.e05
    LEFT JOIN cnt AS scnt
        ON scnt.c01 = scity.d03
    WHERE p.p06 >= '2005-01-01'
      AND p.p06 <  '2006-01-01'
    GROUP BY
        p.p02,
        date(p.p06),
        cg.customer_country
),
daily_with_history AS (
    SELECT
        pd.*,
        COALESCE((
            SELECT AVG(pd2.day_payment_amount)
            FROM payments_day AS pd2
            WHERE pd2.customer_id = pd.customer_id
              AND pd2.payment_date >= date(pd.payment_date, '-30 day')
              AND pd2.payment_date <  pd.payment_date
        ), 0.0) AS avg_daily_amount_prev_30d
    FROM payments_day AS pd
),
flagged AS (
    SELECT
        dwh.*,
        (dwh.day_payment_amount / NULLIF(dwh.avg_daily_amount_prev_30d, 0.0)) AS exceed_ratio,
        EXISTS (
            SELECT 1
            FROM pay AS p
            JOIN stf AS s
                ON s.o01 = p.p03
            JOIN ren AS r
                ON r.q01 = p.p04
            JOIN inv AS i
                ON i.n01 = r.q03
            WHERE p.p02 = dwh.customer_id
              AND date(p.p06) = dwh.payment_date
              AND (
                  SELECT sc.c02
                  FROM stf AS ss
                  JOIN sto AS stost
                      ON stost.j01 = ss.o07
                  JOIN adr AS sa2
                      ON sa2.e01 = stost.j06
                  JOIN cty AS scy2
                      ON scy2.d01 = sa2.e05
                  JOIN cnt AS sc
                      ON sc.c01 = scy2.d03
                  WHERE ss.o01 = s.o01
              ) <> dwh.customer_country
        ) AS has_non_home_store_country_payment
    FROM daily_with_history AS dwh
    WHERE dwh.avg_daily_amount_prev_30d > 0
      AND dwh.payment_count >= 3
      AND dwh.day_payment_amount >= 2.0 * dwh.avg_daily_amount_prev_30d
)
SELECT
    f.customer_id,
    cg.customer_name,
    f.payment_date,
    f.customer_country,
    f.payment_count,
    ROUND(f.day_payment_amount, 2) AS day_payment_amount,
    ROUND(f.avg_daily_amount_prev_30d, 2) AS avg_daily_amount_prev_30d,
    f.distinct_staff_count,
    f.distinct_store_count,
    f.store_countries,
    RANK() OVER (
        PARTITION BY f.customer_country
        ORDER BY f.day_payment_amount / NULLIF(f.avg_daily_amount_prev_30d, 0.0) DESC,
                 f.day_payment_amount DESC
    ) AS suspicion_rank_in_customer_country
FROM flagged AS f
JOIN customer_geo AS cg
  ON cg.customer_id = f.customer_id
WHERE f.has_non_home_store_country_payment = 1
ORDER BY
    f.customer_country,
    suspicion_rank_in_customer_country,
    f.payment_date,
    f.customer_id;