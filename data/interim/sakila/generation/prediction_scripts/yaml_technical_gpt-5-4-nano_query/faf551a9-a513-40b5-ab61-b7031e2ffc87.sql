WITH customer_geo AS (
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
daily_payments AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count,
    GROUP_CONCAT(DISTINCT s.o07) AS store_list
  FROM pay AS p
  JOIN stf AS s ON s.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06)
),
daily_with_baseline AS (
  SELECT
    dp.*,
    (
      SELECT AVG(dp_prev.day_amount)
      FROM daily_payments AS dp_prev
      WHERE dp_prev.customer_id = dp.customer_id
        AND dp_prev.payment_date >= date(dp.payment_date, '-30 days')
        AND dp_prev.payment_date <  dp.payment_date
    ) AS avg_daily_prev_30
  FROM daily_payments AS dp
),
country_daily_rank AS (
  SELECT
    dwp.*,
    PERCENT_RANK() OVER (
      PARTITION BY cg.country_name, dwp.payment_date
      ORDER BY dwp.day_amount
    ) AS pr
  FROM daily_with_baseline AS dwp
  JOIN customer_geo AS cg
    ON cg.customer_id = dwp.customer_id
),
country_p95_threshold AS (
  SELECT
    cg.country_name,
    dp.payment_date,
    (
      SELECT MIN(t.day_amount)
      FROM daily_with_baseline AS t
      JOIN customer_geo AS cg2 ON cg2.customer_id = t.customer_id
      WHERE cg2.country_name = cg.country_name
        AND t.avg_daily_prev_30 IS NOT NULL
        AND t.payment_date = dp.payment_date
      ORDER BY t.day_amount DESC
      LIMIT 1 OFFSET CAST(0.05 * (
        SELECT COUNT(*)
        FROM daily_with_baseline AS x
        JOIN customer_geo AS cg3 ON cg3.customer_id = x.customer_id
        WHERE cg3.country_name = cg.country_name
          AND x.avg_daily_prev_30 IS NOT NULL
          AND x.payment_date = dp.payment_date
      ) AS INT)
    ) AS p95_threshold_dummy
  FROM daily_with_baseline AS dp
  JOIN customer_geo AS cg
    ON cg.customer_id = dp.customer_id
  GROUP BY cg.country_name, dp.payment_date
),
suspected_days AS (
  SELECT
    dwp.customer_id,
    cg.first_name,
    cg.last_name,
    cg.country_name,
    cg.city_name,
    dwp.payment_date,
    dwp.payment_count,
    ROUND(dwp.day_amount, 2) AS day_amount,
    ROUND(dwp.avg_daily_prev_30, 2) AS avg_daily_prev_30,
    ROUND(dwp.day_amount - dwp.avg_daily_prev_30, 2) AS deviation_from_avg,
    dwp.store_list,
    -- rank by spike within country
    RANK() OVER (
      PARTITION BY cg.country_name
      ORDER BY (dwp.day_amount - dwp.avg_daily_prev_30) DESC, dwp.day_amount DESC
    ) AS spike_rank_in_country
  FROM daily_with_baseline AS dwp
  JOIN customer_geo AS cg
    ON cg.customer_id = dwp.customer_id
  WHERE dwp.avg_daily_prev_30 IS NOT NULL
    AND dwp.day_amount >= 3.0 * dwp.avg_daily_prev_30
    AND dwp.day_amount > (
      SELECT
        -- 95th percentile among customers of same country for this day
        t.p95
      FROM (
        SELECT
          cg2.country_name,
          dp2.payment_date,
          (
            SELECT dp3.day_amount
            FROM daily_with_baseline AS dp3
            JOIN customer_geo AS cg3 ON cg3.customer_id = dp3.customer_id
            WHERE cg3.country_name = cg2.country_name
              AND dp3.payment_date = dp2.payment_date
              AND dp3.avg_daily_prev_30 IS NOT NULL
            ORDER BY dp3.day_amount
            LIMIT 1 OFFSET CAST(0.95 * (
              SELECT COUNT(*)
              FROM daily_with_baseline AS dp4
              JOIN customer_geo AS cg4 ON cg4.customer_id = dp4.customer_id
              WHERE cg4.country_name = cg2.country_name
                AND dp4.payment_date = dp2.payment_date
                AND dp4.avg_daily_prev_30 IS NOT NULL
            ) AS INT) - 1
          ) AS p95
        FROM daily_with_baseline AS dp2
        JOIN customer_geo AS cg2 ON cg2.customer_id = dp2.customer_id
        WHERE dp2.customer_id = dwp.customer_id
        LIMIT 1
      ) AS t
    )
)
SELECT
  sd.payment_date AS spike_date,
  sd.first_name,
  sd.last_name,
  sd.country_name AS country,
  sd.city_name AS city,
  sd.store_list AS store,
  sd.payment_count,
  sd.day_amount,
  sd.avg_daily_prev_30 AS avg_prev_30_days,
  sd.deviation_from_avg,
  sd.spike_rank_in_country AS customer_spike_rank_in_country
FROM suspected_days AS sd
ORDER BY
  sd.country,
  sd.spike_rank_in_country,
  sd.spike_date,
  sd.customer_id;