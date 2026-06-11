WITH customer_geo AS (
  SELECT
    cus.h01 AS customer_id,
    cus.h03 AS first_name,
    cus.h04 AS last_name,
    cty.d02 AS city,
    cnt.c02 AS country,
    cnt.c01 AS country_id
  FROM cus
  JOIN adr ON adr.e01 = cus.h06
  JOIN cty ON cty.d01 = adr.e05
  JOIN cnt ON cnt.c01 = cty.d03
),
pay_daily AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_sum,
    MAX(CAST(p.p05 AS REAL)) AS max_payment,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay p
  JOIN stf s ON s.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06)
),
daily_with_prev30 AS (
  SELECT
    pd.*,
    (
      SELECT AVG(pd2.day_sum)
      FROM pay_daily pd2
      WHERE pd2.customer_id = pd.customer_id
        AND pd2.payment_date >= date(pd.payment_date, '-30 days')
        AND pd2.payment_date < pd.payment_date
    ) AS avg_prev30_day_sum
  FROM pay_daily pd
),
r_de_comp AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    SUM(
      CASE
        WHEN cat_r.mpaa_rating IN ('R','NC-17') THEN CAST(p.p05 AS REAL)
        ELSE 0
      END
    ) AS r_nc17_sum
  FROM pay p
  LEFT JOIN ren r
    ON r.q01 = p.p04
  LEFT JOIN inv i
    ON i.n01 = r.q03
  LEFT JOIN flm f
    ON f.i01 = i.n02
  CROSS JOIN (
    SELECT f2.i11 AS mpaa_rating
    FROM flm f2
    WHERE 1=0
  ) AS cat_r
  JOIN flm f ON f.i01 = i.n02
  WHERE f.i11 IN ('R','NC-17') OR f.i11 NOT IN ('R','NC-17')
  GROUP BY
    p.p02,
    date(p.p06)
),
daily_with_r_share AS (
  SELECT
    d.*,
    COALESCE(rd.r_nc17_sum, 0.0) AS r_nc17_sum,
    CASE
      WHEN d.day_sum > 0 THEN COALESCE(rd.r_nc17_sum, 0.0) / d.day_sum
      ELSE 0.0
    END AS r_nc17_share
  FROM daily_with_prev30 d
  LEFT JOIN (
    SELECT
      p.p02 AS customer_id,
      date(p.p06) AS payment_date,
      SUM(CAST(p.p05 AS REAL)) AS r_nc17_sum
    FROM pay p
    JOIN ren r ON r.q01 = p.p04
    JOIN inv i ON i.n01 = r.q03
    JOIN flm f ON f.i01 = i.n02
    WHERE f.i11 IN ('R','NC-17')
    GROUP BY p.p02, date(p.p06)
  ) rd
    ON rd.customer_id = d.customer_id
   AND rd.payment_date = d.payment_date
),
qualified_days AS (
  SELECT
    d.customer_id,
    d.payment_date,
    d.payment_count,
    d.day_sum,
    d.max_payment,
    d.staff_count,
    d.store_count,
    d.avg_prev30_day_sum,
    d.r_nc17_share
  FROM daily_with_r_share d
  WHERE d.avg_prev30_day_sum IS NOT NULL
    AND d.avg_prev30_day_sum > 0
    AND d.payment_count >= 3
    AND d.day_sum >= 3 * d.avg_prev30_day_sum
    AND (d.staff_count >= 2 OR d.store_count >= 2)
),
ranked AS (
  SELECT
    q.*,
    cg.city,
    cg.country,
    RANK() OVER (
      PARTITION BY cg.country_id, q.payment_date
      ORDER BY q.day_sum DESC
    ) AS day_rank_in_country
  FROM qualified_days q
  JOIN customer_geo cg ON cg.customer_id = q.customer_id
)
SELECT
  r.customer_id,
  r.city,
  r.country,
  r.payment_date,
  r.payment_count,
  ROUND(r.day_sum, 2) AS day_sum,
  ROUND(r.max_payment, 2) AS max_payment,
  ROUND(r.r_nc17_share, 4) AS r_nc17_rental_payment_share,
  r.day_rank_in_country
FROM ranked r
ORDER BY
  r.country,
  r.payment_date,
  r.day_rank_in_country,
  r.customer_id;