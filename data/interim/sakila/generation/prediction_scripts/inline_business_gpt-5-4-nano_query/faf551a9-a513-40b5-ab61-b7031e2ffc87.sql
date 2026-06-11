WITH payment_base AS (
    SELECT
        p.p01 AS payment_id,
        p.p02 AS customer_id,
        p.p03 AS staff_id,
        p.p05 AS amount,
        DATE(p.p06) AS day_date,
        s.o07 AS store_id
    FROM pay AS p
    JOIN stf AS s ON s.o01 = p.p03
),
customer_geo AS (
    SELECT
        c.h01 AS customer_id,
        c.h03 AS first_name,
        c.h04 AS last_name,
        co.c02 AS country_name,
        ci.d02 AS city_name
    FROM cus AS c
    JOIN adr AS a ON a.e01 = c.h06
    JOIN cty AS ci ON ci.d01 = a.e05
    JOIN cnt AS co ON co.c01 = ci.d03
),
daily_by_customer AS (
    SELECT
        pb.customer_id,
        cg.first_name,
        cg.last_name,
        cg.country_name,
        cg.city_name,
        pb.day_date,
        COUNT(*) AS payment_count,
        SUM(CAST(pb.amount AS REAL)) AS day_amount,
        COUNT(DISTINCT pb.staff_id) AS distinct_staff_count,
        COUNT(DISTINCT pb.store_id) AS distinct_store_count
    FROM payment_base AS pb
    JOIN customer_geo AS cg ON cg.customer_id = pb.customer_id
    GROUP BY
        pb.customer_id, cg.first_name, cg.last_name, cg.country_name, cg.city_name, pb.day_date
),
with_personal_avg AS (
    SELECT
        dbc.*,
        (
            SELECT AVG(dbc_prev.day_amount)
            FROM daily_by_customer AS dbc_prev
            WHERE dbc_prev.customer_id = dbc.customer_id
              AND dbc_prev.day_date >= DATE(dbc.day_date, '-30 day')
              AND dbc_prev.day_date < dbc.day_date
        ) AS avg_prev_30d
    FROM daily_by_customer AS dbc
),
daily_ranked_by_country AS (
    SELECT
        wpa.*,
        dp95.p95_day_amount,
        RANK() OVER (
            PARTITION BY wpa.country_name
            ORDER BY (wpa.day_amount / NULLIF(wpa.avg_prev_30d, 0)) DESC,
                     wpa.day_amount DESC,
                     wpa.customer_id
        ) AS country_surge_rank
    FROM with_personal_avg AS wpa
    JOIN (
        SELECT country_name, day_amount, p95_day_amount
        FROM (
            SELECT
                country_name,
                day_amount,
                day_amount AS p95_day_amount,
                ROW_NUMBER() OVER (PARTITION BY country_name ORDER BY day_amount DESC) AS rn,
                COUNT(*) OVER (PARTITION BY country_name) AS cnt
            FROM daily_by_customer
        ) x
        WHERE rn = CAST(CEIL(0.05 * cnt) AS INT)  -- threshold at 95th percentile (approx by rank)
    ) dp95
      ON dp95.country_name = wpa.country_name
)
SELECT
    wpa.day_date AS surge_date,
    wpa.first_name,
    wpa.last_name,
    wpa.country_name AS country,
    wpa.city_name AS city,
    d.store_id AS store_id,
    wpa.payment_count,
    ROUND(wpa.day_amount, 2) AS day_amount,
    ROUND(wpa.avg_prev_30d, 2) AS avg_prev_30d,
    ROUND(wpa.day_amount - wpa.avg_prev_30d, 2) AS deviation_from_avg,
    RANK() OVER (
        PARTITION BY wpa.country_name
        ORDER BY (wpa.day_amount / NULLIF(wpa.avg_prev_30d, 0)) DESC,
                 wpa.day_amount DESC,
                 wpa.customer_id
    ) AS country_surge_rank
FROM with_personal_avg AS wpa
JOIN (
    SELECT
        pb.customer_id,
        pb.day_date,
        COUNT(*) AS cnt,
        -- store with max payments sum on that day for that customer
        FIRST_VALUE(pb.store_id) OVER (
            PARTITION BY pb.customer_id, pb.day_date
            ORDER BY SUM(CAST(pb.amount AS REAL)) DESC
        ) AS store_id
    FROM payment_base AS pb
    GROUP BY pb.customer_id, pb.day_date, pb.store_id
) d
  ON d.customer_id = wpa.customer_id
 AND d.day_date = wpa.day_date
WHERE wpa.avg_prev_30d IS NOT NULL
  AND wpa.avg_prev_30d > 0
  AND wpa.day_amount >= 3.0 * wpa.avg_prev_30d
  AND wpa.day_amount > (
      SELECT p95_val
      FROM (
          SELECT
              day_amount AS p95_val,
              ROW_NUMBER() OVER (ORDER BY day_amount DESC) AS rn,
              COUNT(*) OVER () AS cnt_all
          FROM daily_by_customer AS d95
          WHERE d95.country_name = wpa.country_name
      ) t
      WHERE rn = CAST(CEIL(0.05 * cnt_all) AS INT)
  )
ORDER BY
    wpa.country_name,
    country_surge_rank,
    wpa.day_date,
    wpa.customer_id;