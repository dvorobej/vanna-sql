WITH payment_enriched AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        s.o02 || ' ' || s.o03 AS staff_name,
        s.o07 AS store_id,
        DATE(p.p06) AS payment_date,
        CAST(p.p05 AS REAL) AS amount,
        c.h03 || ' ' || c.h04 AS customer_name,
        ci.d02 AS city_name,
        co.c02 AS country_name
    FROM pay AS p
    JOIN cus AS c
        ON c.h01 = p.p02
    JOIN adr AS a
        ON a.e01 = c.h06
    JOIN cty AS ci
        ON ci.d01 = a.e05
    JOIN cnt AS co
        ON co.c01 = ci.d03
    JOIN stf AS s
        ON s.o01 = p.p03
),
daily_agg AS (
    SELECT
        customer_id,
        customer_name,
        city_name,
        country_name,
        payment_date,
        COUNT(*) AS payment_count,
        SUM(amount) AS day_sum,
        COUNT(DISTINCT staff_id) AS staff_count,
        COUNT(DISTINCT store_id) AS store_count,
        MIN(payment_id) AS first_payment_id,
        MAX(payment_id) AS last_payment_id,
        MIN(amount) AS min_payment_amount,
        MAX(amount) AS max_payment,
        MIN(payment_date || ' ' || first_time_dummy) AS first_op_dummy
    FROM payment_enriched
    GROUP BY
        customer_id, customer_name, city_name, country_name, payment_date
),
daily_agg2 AS (
    SELECT
        d.*,
        (SELECT MIN(pe.payment_id) FROM payment_enriched pe WHERE pe.customer_id = d.customer_id AND pe.payment_date = d.payment_date) AS first_payment_id2,
        (SELECT MAX(pe.payment_id) FROM payment_enriched pe WHERE pe.customer_id = d.customer_id AND pe.payment_date = d.payment_date) AS last_payment_id2,
        (SELECT MIN(pe.payment_id) FROM payment_enriched pe WHERE pe.customer_id = d.customer_id AND pe.payment_date = d.payment_date) AS first_payment_id3
    FROM daily_agg d
),
history_stats AS (
    SELECT
        pe.customer_id,
        pe.customer_name,
        pe.city_name,
        pe.country_name,
        AVG(day_sum) AS customer_avg_day_amount,
        (
          SELECT day_sum
          FROM (
            SELECT
              d2.day_sum,
              ROW_NUMBER() OVER (
                PARTITION BY d2.customer_id
                ORDER BY d2.day_sum
              ) AS rn,
              COUNT(*) OVER (PARTITION BY d2.customer_id) AS cnt
            FROM (
              SELECT
                customer_id,
                payment_date,
                SUM(amount) AS day_sum
              FROM payment_enriched
              GROUP BY customer_id, payment_date
            ) d2
          ) t
          WHERE rn = CAST((0.95 * cnt) AS INT)
        ) AS customer_p95_day_amount
    FROM (
      SELECT
        customer_id,
        customer_name,
        city_name,
        country_name,
        payment_date,
        SUM(amount) AS day_sum
      FROM payment_enriched
      GROUP BY customer_id, customer_name, city_name, country_name, payment_date
    ) pe
    GROUP BY pe.customer_id, pe.customer_name, pe.city_name, pe.country_name
),
country_p95 AS (
    SELECT
        country_name,
        MIN(day_sum) AS country_p95_day_amount
    FROM (
        SELECT
            country_name,
            day_sum,
            ROW_NUMBER() OVER (PARTITION BY country_name ORDER BY day_sum) AS rn,
            COUNT(*) OVER (PARTITION BY country_name) AS cnt
        FROM (
            SELECT
                payment_enriched.country_name,
                payment_enriched.payment_date,
                SUM(payment_enriched.amount) AS day_sum
            FROM payment_enriched
            GROUP BY payment_enriched.country_name, payment_enriched.payment_date
        ) dd
    ) r
    WHERE rn >= CAST(0.95 * cnt AS INT)
    GROUP BY country_name
),
daily_scored AS (
    SELECT
        da.customer_id,
        da.customer_name,
        da.city_name,
        da.country_name,
        da.payment_date,
        da.payment_count,
        da.day_sum,
        da.staff_count,
        da.store_count,
        da.max_payment,
        (da.day_sum - hs.customer_avg_day_amount) AS deviation_from_customer_avg,
        hs.customer_avg_day_amount,
        hs.customer_p95_day_amount,
        cp.country_p95_day_amount,
        RANK() OVER (
            PARTITION BY da.country_name
            ORDER BY da.day_sum DESC
        ) AS suspicion_rank
    FROM (
        SELECT
            customer_id,
            customer_name,
            city_name,
            country_name,
            payment_date,
            COUNT(*) AS payment_count,
            SUM(amount) AS day_sum,
            COUNT(DISTINCT staff_id) AS staff_count,
            COUNT(DISTINCT store_id) AS store_count,
            MAX(amount) AS max_payment
        FROM payment_enriched
        GROUP BY customer_id, customer_name, city_name, country_name, payment_date
    ) da
    JOIN history_stats hs
        ON hs.customer_id = da.customer_id
       AND hs.country_name = da.country_name
    JOIN country_p95 cp
        ON cp.country_name = da.country_name
    WHERE da.payment_count >= 3
      AND da.staff_count >= 2
      AND da.store_count >= 1
      AND da.day_sum > hs.customer_avg_day_amount
      AND da.day_sum > cp.country_p95_day_amount
),
ops_times AS (
    SELECT
        customer_id,
        payment_date,
        MIN(p06) AS first_op_time,
        MAX(p06) AS last_op_time
    FROM pay AS p
    GROUP BY customer_id, DATE(p.p06)
)
SELECT
    ds.customer_name,
    ds.city_name,
    ds.country_name,
    ds.payment_date,
    ROUND(ds.day_sum, 2) AS day_sum,
    ds.payment_count,
    ds.staff_count,
    ds.store_count,
    ot.first_op_time AS first_operation_time,
    ot.last_op_time AS last_operation_time,
    ROUND(ds.max_payment, 2) AS max_payment,
    ds.suspicion_rank AS suspicion_rank_in_country
FROM daily_scored ds
JOIN ops_times ot
  ON ot.customer_id = ds.customer_id
 AND ot.payment_date = ds.payment_date
ORDER BY
    ds.country_name,
    ds.suspicion_rank,
    ds.day_sum DESC,
    ds.payment_date;