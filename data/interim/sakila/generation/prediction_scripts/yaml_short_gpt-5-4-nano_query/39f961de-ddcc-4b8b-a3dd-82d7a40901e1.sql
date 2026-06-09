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
pay_enriched AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    cg.country_id,
    cg.city,
    cg.country,
    date(p.p06) AS payment_date,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p03 AS staff_id,
    s.o07 AS store_id,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM ren r
        JOIN inv i ON i.n01 = r.q03
        JOIN flm f ON f.i01 = i.n02
        JOIN ren r2 ON r2.q01 = p.p04
        WHERE r2.q01 = p.p04
          AND f.i11 IN ('R','NC-17')
      )
      THEN 1 ELSE 0
    END AS is_r_or_nc17_film
  FROM pay p
  JOIN customer_geo cg ON cg.customer_id = p.p02
  JOIN stf s ON s.o01 = p.p03
),
daily AS (
  SELECT
    customer_id,
    country_id,
    city,
    country,
    payment_date,
    COUNT(*) AS payment_count,
    SUM(payment_amount) AS day_sum,
    MAX(payment_amount) AS max_payment,
    COUNT(DISTINCT staff_id) AS staff_cnt,
    COUNT(DISTINCT store_id) AS store_cnt,
    SUM(is_r_or_nc17_film) AS r_or_nc17_payment_cnt
  FROM pay_enriched
  GROUP BY customer_id, country_id, city, country, payment_date
),
daily_with_history AS (
  SELECT
    d.*,
    (
      SELECT AVG(d2.day_sum)
      FROM daily d2
      WHERE d2.customer_id = d.customer_id
        AND d2.payment_date >= date(d.payment_date, '-30 days')
        AND d2.payment_date < d.payment_date
    ) AS avg_prev_30d
  FROM daily d
),
qualifying_days AS (
  SELECT
    dwh.*,
    (dwh.day_sum / NULLIF(dwh.avg_prev_30d, 0)) AS ratio_to_avg
  FROM daily_with_history dwh
  WHERE dwh.avg_prev_30d IS NOT NULL
    AND dwh.avg_prev_30d > 0
    AND dwh.day_sum >= 3 * dwh.avg_prev_30d
    AND dwh.payment_count >= 3
    AND (dwh.staff_cnt >= 2 OR dwh.store_cnt >= 2)
)
SELECT
  qd.customer_id,
  cg.first_name,
  cg.last_name,
  qd.city,
  qd.country,
  qd.payment_date,
  qd.payment_count,
  ROUND(qd.day_sum, 2) AS day_sum,
  ROUND(qd.max_payment, 2) AS max_payment,
  ROUND(1.0 * qd.r_or_nc17_payment_cnt / qd.payment_count, 4) AS r_or_nc17_rental_share,
  DENSE_RANK() OVER (
    PARTITION BY qd.country_id, qd.payment_date
    ORDER BY qd.day_sum DESC
  ) AS day_rank_within_country_by_sum
FROM qualifying_days qd
JOIN customer_geo cg
  ON cg.customer_id = qd.customer_id
ORDER BY
  qd.country,
  qd.payment_date,
  day_rank_within_country_by_sum,
  qd.customer_id;