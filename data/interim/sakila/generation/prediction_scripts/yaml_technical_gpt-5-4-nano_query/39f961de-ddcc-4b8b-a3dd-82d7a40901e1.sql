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
daily_payments AS (
  SELECT
    p.p02 AS customer_id,
    cg.city,
    cg.country,
    cg.country_id,
    date(p.p06) AS payment_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_sum,
    MAX(CAST(p.p05 AS REAL)) AS max_single_payment,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT s.o07) AS distinct_store_count
  FROM pay AS p
  JOIN customer_geo AS cg ON cg.customer_id = p.p02
  JOIN stf AS s ON s.o01 = p.p03
  GROUP BY
    p.p02,
    cg.city,
    cg.country,
    cg.country_id,
    date(p.p06)
),
daily_with_history AS (
  SELECT
    dp.*,
    (
      SELECT AVG(dp2.day_sum)
      FROM daily_payments AS dp2
      WHERE dp2.customer_id = dp.customer_id
        AND dp2.payment_date >= date(dp.payment_date, '-30 days')
        AND dp2.payment_date < dp.payment_date
    ) AS avg_prev_30d_day_sum
  FROM daily_payments AS dp
),
daily_with_r_share AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    SUM(
      CASE
        WHEN EXISTS (
          SELECT 1
          FROM ren r
          JOIN inv i ON i.n01 = r.q03
          WHERE r.q01 = p.p04
            AND EXISTS (
              SELECT 1
              FROM flm f
              WHERE f.i01 = i.n02
                AND f.i11 IN ('R','NC-17')
            )
        )
        THEN CAST(p.p05 AS REAL)
        ELSE 0.0
      END
    ) AS r_or_nc17_amount,
    SUM(CAST(p.p05 AS REAL)) AS day_sum_check
  FROM pay AS p
  GROUP BY p.p02, date(p.p06)
),
suspicious_days AS (
  SELECT
    dwh.customer_id,
    dwh.city,
    dwh.country,
    dwh.country_id,
    dwh.payment_date,
    dwh.payment_count,
    dwh.day_sum,
    dwh.max_single_payment,
    dwh.distinct_staff_count,
    dwh.distinct_store_count,
    dwh.avg_prev_30d_day_sum,
    COALESCE(dwr.r_or_nc17_amount / NULLIF(dwr.day_sum_check, 0), 0.0) AS r_or_nc17_rental_share
  FROM daily_with_history AS dwh
  JOIN daily_with_r_share AS dwr
    ON dwr.customer_id = dwh.customer_id
   AND dwr.payment_date = dwh.payment_date
  WHERE dwh.avg_prev_30d_day_sum IS NOT NULL
    AND dwh.avg_prev_30d_day_sum > 0
    AND dwh.payment_count >= 3
    AND dwh.day_sum >= 3.0 * dwh.avg_prev_30d_day_sum
    AND (dwh.distinct_staff_count >= 2 OR dwh.distinct_store_count >= 2)
),
ranked AS (
  SELECT
    sd.*,
    DENSE_RANK() OVER (
      PARTITION BY sd.country_id, sd.payment_date
      ORDER BY sd.day_sum DESC
    ) AS day_rank_in_country
  FROM suspicious_days sd
)
SELECT
  r.customer_id,
  cg.first_name,
  cg.last_name,
  r.city,
  r.country,
  r.payment_date,
  r.payment_count,
  ROUND(r.day_sum, 2) AS day_sum,
  ROUND(r.max_single_payment, 2) AS max_single_payment,
  ROUND(r.r_or_nc17_rental_share, 4) AS r_or_nc17_rental_share,
  r.day_rank_in_country
FROM ranked r
JOIN cus cg ON cg.h01 = r.customer_id
ORDER BY
  r.country,
  r.day_rank_in_country,
  r.payment_date,
  r.customer_id;