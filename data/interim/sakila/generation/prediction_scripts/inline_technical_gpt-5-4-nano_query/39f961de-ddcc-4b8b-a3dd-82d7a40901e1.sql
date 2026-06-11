WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    c.h02 AS registration_store_id,
    c.h07 AS active_status,
    ct.c01 AS country_id,
    ct.c02 AS country_name,
    cy.d02 AS city_name
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS cy ON cy.d01 = a.e05
  JOIN cnt AS ct ON ct.c01 = cy.d03
),
pay_daily AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS pay_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_sum,
    MAX(CAST(p.p05 AS REAL)) AS max_payment,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT s.o07) AS distinct_store_count
  FROM pay AS p
  JOIN stf AS s ON s.o01 = p.p03
  GROUP BY p.p02, date(p.p06)
),
pay_daily_with_hist AS (
  SELECT
    pd.*,
    (
      SELECT AVG(pd2.day_sum)
      FROM pay_daily AS pd2
      WHERE pd2.customer_id = pd.customer_id
        AND pd2.pay_date >= date(pd.pay_date, '-30 days')
        AND pd2.pay_date < pd.pay_date
    ) AS avg_prev_30_day_sum
  FROM pay_daily AS pd
),
r_rated_payment_daily AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS pay_date,
    SUM(
      CASE
        WHEN ca_mp.is_rated = 1 THEN CAST(p.p05 AS REAL)
        ELSE 0.0
      END
    ) AS r_nc17_day_sum
  FROM pay AS p
  LEFT JOIN ren r ON r.q01 = p.p04
  LEFT JOIN inv i ON i.n01 = r.q03
  LEFT JOIN flm m ON m.i01 = i.n02
  LEFT JOIN (
    SELECT i01, CASE WHEN m.i11 IN ('R','NC-17') THEN 1 ELSE 0 END AS is_rated
    FROM flm
  ) ca_mp ON ca_mp.i01 = m.i01
  GROUP BY p.p02, date(p.p06)
),
daily_calc AS (
  SELECT
    pd.customer_id,
    pd.pay_date,
    pd.payment_count,
    pd.day_sum,
    pd.max_payment,
    pd.distinct_staff_count,
    pd.distinct_store_count,
    pdwh.avg_prev_30_day_sum,
    COALESCE(rr.r_nc17_day_sum, 0.0) AS r_nc17_day_sum
  FROM pay_daily_with_hist pdwh
  JOIN pay_daily pd
    ON pd.customer_id = pdwh.customer_id
   AND pd.pay_date = pdwh.pay_date
  LEFT JOIN r_rated_payment_daily rr
    ON rr.customer_id = pd.customer_id
   AND rr.pay_date = pd.pay_date
  CROSS JOIN (SELECT 1) dummy
  WHERE 1=1
),
daily_filtered AS (
  SELECT
    dc.*,
    (dc.day_sum / dc.avg_prev_30_day_sum) AS spike_ratio,
    (CASE WHEN dc.day_sum > 0 THEN dc.r_nc17_day_sum / dc.day_sum ELSE 0.0 END) AS r_nc17_payment_share
  FROM daily_calc dc
  WHERE dc.avg_prev_30_day_sum IS NOT NULL
    AND dc.avg_prev_30_day_sum > 0
    AND dc.day_sum >= 3.0 * dc.avg_prev_30_day_sum
    AND dc.payment_count >= 3
    AND (dc.distinct_staff_count >= 2 OR dc.distinct_store_count >= 2)
),
ranked_in_country AS (
  SELECT
    df.*,
    DENSE_RANK() OVER (
      PARTITION BY cg.country_id, df.pay_date
      ORDER BY df.day_sum DESC
    ) AS day_rank_in_country
  FROM daily_filtered df
  JOIN customer_geo cg ON cg.customer_id = df.customer_id
)
SELECT
  ric.customer_id,
  cg.city_name AS city,
  cg.country_name AS country,
  ric.pay_date AS spike_date,
  ric.payment_count,
  ROUND(ric.day_sum, 2) AS day_sum,
  ROUND(ric.max_payment, 2) AS max_payment,
  ROUND(ric.r_nc17_payment_share, 4) AS r_nc17_payment_share,
  ric.day_rank_in_country
FROM ranked_in_country ric
JOIN customer_geo cg ON cg.customer_id = ric.customer_id
ORDER BY
  cg.country_name,
  ric.pay_date,
  ric.day_rank_in_country,
  ric.customer_id;