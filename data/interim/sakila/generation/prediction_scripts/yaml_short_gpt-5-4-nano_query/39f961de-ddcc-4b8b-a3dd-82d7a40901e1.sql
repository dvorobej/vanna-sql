WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    ct.d02 AS city,
    co.c02 AS country,
    co.c01 AS country_id
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ct ON ct.d01 = a.e05
  JOIN cnt AS co ON co.c01 = ct.d03
),
pay_daily AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_sum,
    MAX(CAST(p.p05 AS REAL)) AS max_payment,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT COALESCE(i.n03, s.o07)) AS distinct_store_count
  FROM pay AS p
  LEFT JOIN ren AS r ON r.q01 = p.p04
  LEFT JOIN inv AS i ON i.n01 = r.q03
  LEFT JOIN stf AS s ON s.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06)
),
day_r_value AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    SUM(
      CASE
        WHEN ca.r_present THEN CAST(p.p05 AS REAL)
        ELSE 0.0
      END
    ) AS day_sum_r_nc
  FROM pay AS p
  LEFT JOIN ren r ON r.q01 = p.p04
  LEFT JOIN inv i ON i.n01 = r.q03
  LEFT JOIN flm f ON f.i01 = i.n02
  LEFT JOIN (
    SELECT 1 AS r_present
  ) dummy ON 1=1
  CROSS JOIN (
    SELECT
      CASE WHEN f.i11 IN ('R','NC-17') THEN 1 ELSE 0 END AS r_present
  ) ca
  GROUP BY
    p.p02,
    date(p.p06)
),
daily_with_avgs AS (
  SELECT
    pd.*,
    (
      SELECT AVG(pd2.day_sum)
      FROM pay_daily AS pd2
      WHERE pd2.customer_id = pd.customer_id
        AND pd2.payment_date >= date(pd.payment_date, '-30 day')
        AND pd2.payment_date < pd.payment_date
    ) AS avg_prev_30_day_sum
  FROM pay_daily AS pd
),
suspicious_days AS (
  SELECT
    dwa.*,
    ROUND(
      COALESCE(drv.day_sum_r_nc, 0.0) / NULLIF(dwa.day_sum, 0.0),
      4
    ) AS r_nc17_rental_share
  FROM daily_with_avgs dwa
  LEFT JOIN (
    SELECT
      p.p02 AS customer_id,
      date(p.p06) AS payment_date,
      SUM(CAST(p.p05 AS REAL)) AS day_sum_r_nc
    FROM pay p
    JOIN ren r ON r.q01 = p.p04
    JOIN inv i ON i.n01 = r.q03
    JOIN flm f ON f.i01 = i.n02
    WHERE f.i11 IN ('R','NC-17')
    GROUP BY p.p02, date(p.p06)
  ) drv
    ON drv.customer_id = dwa.customer_id
   AND drv.payment_date = dwa.payment_date
  WHERE dwa.avg_prev_30_day_sum IS NOT NULL
    AND dwa.avg_prev_30_day_sum > 0
    AND dwa.day_sum >= 3 * dwa.avg_prev_30_day_sum
    AND dwa.payment_count >= 3
    AND (dwa.distinct_staff_count >= 2 OR dwa.distinct_store_count >= 2)
),
country_day_ranks AS (
  SELECT
    sd.*,
    DENSE_RANK() OVER (
      PARTITION BY cg.country_id, sd.payment_date
      ORDER BY sd.day_sum DESC
    ) AS day_rank_in_country
  FROM suspicious_days sd
  JOIN customer_geo cg ON cg.customer_id = sd.customer_id
)
SELECT
  cgj.first_name,
  cgj.last_name,
  cgj.city,
  cgj.country,
  sd.payment_date,
  sd.payment_count,
  ROUND(sd.day_sum, 2) AS day_sum,
  ROUND(sd.max_payment, 2) AS max_payment,
  ROUND(sd.r_nc17_rental_share, 4) AS r_nc17_rental_share,
  cdr.day_rank_in_country AS country_day_rank_in_sum
FROM country_day_ranks sd
JOIN customer_geo cgj ON cgj.customer_id = sd.customer_id
JOIN country_day_ranks cdr
  ON cdr.customer_id = sd.customer_id
 AND cdr.payment_date = sd.payment_date
ORDER BY
  sd.payment_date,
  cgj.country,
  cdr.day_rank_in_country,
  cgj.last_name,
  cgj.first_name;