WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    c.h06 AS address_id,
    ci.d02 AS city,
    cnt.c02 AS country
  FROM cus c
  JOIN adr a ON a.e01 = c.h06
  JOIN cty ci ON ci.d01 = a.e05
  JOIN cnt cnt ON cnt.c01 = ci.d03
),
inv_rent AS (
  SELECT
    r.q01 AS rent_id,
    i.n02 AS film_id,
    i.n01 AS inventory_id
  FROM ren r
  JOIN inv i ON i.n01 = r.q03
),
daily_payments AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_sum,
    MAX(CAST(p.p05 AS REAL)) AS max_payment,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT (
      CASE
        WHEN s.o07 IS NOT NULL THEN s.o07
        ELSE NULL
      END
    )) AS staff_store_count,
    SUM(CASE
          WHEN ca.i11 IN ('R','NC-17') THEN 1
          ELSE 0
        END) * 1.0 / COUNT(*) AS r_nc17_rental_share_by_count
  FROM pay p
  JOIN stf s ON s.o01 = p.p03
  JOIN customer_geo cg ON cg.customer_id = p.p02
  LEFT JOIN ren r ON r.q01 = p.p04
  LEFT JOIN inv i ON i.n01 = r.q03
  LEFT JOIN flm ca ON ca.i01 = i.n02
  GROUP BY p.p02, date(p.p06)
),
calendar_with_prev AS (
  SELECT
    dp.*,
    (
      SELECT AVG(CAST(prev.day_sum AS REAL))
      FROM daily_payments prev
      WHERE prev.customer_id = dp.customer_id
        AND prev.payment_date >= date(dp.payment_date, '-30 days')
        AND prev.payment_date < dp.payment_date
    ) AS avg_prev_30d
  FROM daily_payments dp
),
suspicious_days AS (
  SELECT
    cw.*,
    (cw.day_sum - cw.avg_prev_30d) AS deviation_from_avg,
    CASE
      WHEN cw.avg_prev_30d > 0 THEN cw.day_sum / cw.avg_prev_30d
      ELSE NULL
    END AS ratio_to_avg
  FROM calendar_with_prev cw
  WHERE cw.avg_prev_30d IS NOT NULL
    AND cw.avg_prev_30d > 0
    AND cw.day_sum >= 3 * cw.avg_prev_30d
    AND cw.payment_count >= 3
    AND (cw.distinct_staff_count >= 2 OR cw.staff_store_count >= 2)
),
ranked AS (
  SELECT
    sd.*,
    DENSE_RANK() OVER (
      PARTITION BY cg.country
      ORDER BY sd.day_sum DESC
    ) AS day_rank_in_country
  FROM suspicious_days sd
  JOIN customer_geo cg ON cg.customer_id = sd.customer_id
)
SELECT
  sd.customer_id,
  cg.city,
  cg.country,
  sd.payment_date,
  sd.payment_count,
  ROUND(sd.day_sum, 2) AS day_sum,
  ROUND(sd.max_payment, 2) AS max_payment,
  ROUND(sd.r_nc17_rental_share_by_count, 4) AS r_nc17_rental_share,
  r.day_rank_in_country
FROM ranked sd
JOIN customer_geo cg ON cg.customer_id = sd.customer_id
ORDER BY
  cg.country,
  r.day_rank_in_country,
  sd.payment_date,
  sd.customer_id;