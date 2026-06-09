WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    ctry.c02 AS country,
    city.d02 AS city
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS city ON city.d01 = a.e05
  JOIN cnt AS ctry ON ctry.c01 = city.d03
),
day_aggr AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS day_date,
    SUM(CAST(p.p05 AS REAL)) AS day_sum,
    COUNT(*) AS payment_count,
    MAX(CAST(p.p05 AS REAL)) AS max_payment,
    COUNT(DISTINCT CASE WHEN st.o01 IS NOT NULL THEN p.p03 END) AS staff_count,
    COUNT(DISTINCT st.o07) AS store_count,
    SUM(CASE
          WHEN flm.i11 IN ('R','NC-17') THEN 1
          ELSE 0
        END) * 1.0 / COUNT(*) AS r_nc17_payment_share
  FROM pay AS p
  JOIN stf AS st ON st.o01 = p.p03
  LEFT JOIN ren AS r ON r.q01 = p.p04
  LEFT JOIN inv AS i ON i.n01 = r.q03
  LEFT JOIN flm ON flm.i01 = i.n01
  GROUP BY
    p.p02,
    date(p.p06)
),
with_prev_avg AS (
  SELECT
    da.*,
    (
      SELECT AVG(d2.day_sum)
      FROM day_aggr AS d2
      WHERE d2.customer_id = da.customer_id
        AND d2.day_date >= date(da.day_date, '-30 days')
        AND d2.day_date < da.day_date
    ) AS avg_prev_30
  FROM day_aggr AS da
),
qualifying_days AS (
  SELECT
    wp.*,
    CASE
      WHEN COALESCE(wp.avg_prev_30, 0) > 0 AND wp.day_sum >= 3.0 * wp.avg_prev_30 THEN 1
      ELSE 0
    END AS spike_flag
  FROM with_prev_avg AS wp
  WHERE wp.avg_prev_30 IS NOT NULL
    AND wp.avg_prev_30 > 0
    AND wp.day_sum >= 3.0 * wp.avg_prev_30
    AND wp.payment_count >= 3
    AND (wp.staff_count >= 2 OR wp.store_count >= 2)
)
SELECT
  cg.city,
  cg.country,
  qd.day_date AS payment_date,
  qd.payment_count,
  ROUND(qd.day_sum, 2) AS day_sum,
  ROUND(qd.max_payment, 2) AS max_payment,
  ROUND(COALESCE(qd.r_nc17_payment_share, 0), 4) AS r_nc17_payment_share,
  RANK() OVER (
    PARTITION BY cg.country
    ORDER BY qd.day_sum DESC
  ) AS day_rank_in_country
FROM qualifying_days AS qd
JOIN customer_geo AS cg ON cg.customer_id = qd.customer_id
ORDER BY
  cg.country,
  day_rank_in_country,
  qd.day_date,
  qd.customer_id;