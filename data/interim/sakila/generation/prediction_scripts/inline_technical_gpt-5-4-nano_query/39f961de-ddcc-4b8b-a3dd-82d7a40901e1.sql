WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cty.d02 AS city,
    cnt.c02 AS country,
    cnt.c01 AS country_id
  FROM cus c
  JOIN adr a ON a.e01 = c.h06
  JOIN cty cty ON cty.d01 = a.e05
  JOIN cnt cnt ON cnt.c01 = cty.d03
),
daily AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS pay_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_sum,
    MAX(CAST(p.p05 AS REAL)) AS max_payment,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay p
  JOIN stf s ON s.o01 = p.p03
  GROUP BY p.p02, date(p.p06)
),
daily_enriched AS (
  SELECT
    d.*,
    (
      SELECT AVG(CAST(d2.day_sum AS REAL))
      FROM daily d2
      WHERE d2.customer_id = d.customer_id
        AND d2.pay_date >= date(d.pay_date, '-30 days')
        AND d2.pay_date < d.pay_date
    ) AS avg_prev_30d
  FROM daily d
),
daily_films_share AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS pay_date,
    SUM(
      CASE
        WHEN flm.i11 IN ('R','NC-17') THEN CAST(p.p05 AS REAL)
        ELSE 0.0
      END
    ) AS r_nc17_amount,
    SUM(CAST(p.p05 AS REAL)) AS total_amount
  FROM pay p
  JOIN ren r ON r.q01 = p.p04
  JOIN inv i ON i.n01 = r.q03
  JOIN flm flm ON flm.i01 = i.n02
  GROUP BY p.p02, date(p.p06)
)
SELECT
  cg.customer_id,
  cg.first_name,
  cg.last_name,
  cg.city,
  cg.country,
  de.pay_date,
  de.payment_count,
  ROUND(de.day_sum, 2) AS day_sum,
  ROUND(de.max_payment, 2) AS max_payment,
  ROUND(
    COALESCE(dfs.r_nc17_amount / NULLIF(dfs.total_amount,0), 0.0),
    4
  ) AS r_nc17_rental_share,
  DENSE_RANK() OVER (
    PARTITION BY cg.country_id, de.pay_date
    ORDER BY de.day_sum DESC
  ) AS day_rank_within_country
FROM daily_enriched de
JOIN customer_geo cg ON cg.customer_id = de.customer_id
JOIN daily_films_share dfs
  ON dfs.customer_id = de.customer_id
 AND dfs.pay_date = de.pay_date
WHERE de.payment_count >= 3
  AND de.avg_prev_30d IS NOT NULL
  AND de.avg_prev_30d > 0
  AND de.day_sum >= 3 * de.avg_prev_30d
  AND (de.staff_count >= 2 OR de.store_count >= 2)
ORDER BY
  cg.country,
  day_rank_within_country,
  de.pay_date,
  de.customer_id;