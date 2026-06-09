WITH customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS first_name,
    c.h04 AS last_name,
    cnt.c02 AS country,
    ci.d02 AS city
  FROM cus AS c
  JOIN adr AS a ON a.e01 = c.h06
  JOIN cty AS ci ON ci.d01 = a.e05
  JOIN cnt ON cnt.c01 = ci.d03
),
inv_risk AS (
  SELECT
    i.n01 AS inventory_id,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM flm f
        WHERE f.i01 = i.n02
          AND f.i11 IN ('R','NC-17')
      )
      THEN 1 ELSE 0
    END AS is_r_rated_or_nc17
  FROM inv i
),
pay_enriched AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    CAST(p.p05 AS REAL) AS payment_amount,
    p.p03 AS staff_id,
    s.o07 AS staff_store_id,
    r.q01 AS rental_id,
    r.q03 AS inventory_id,
    ig.is_r_rated_or_nc17 AS is_r_rated_or_nc17,
    p.p04 AS rental_link
  FROM pay p
  LEFT JOIN ren r ON r.q01 = p.p04
  LEFT JOIN inv_risk ig ON ig.inventory_id = r.q03
  JOIN stf s ON s.o01 = p.p03
),
daily AS (
  SELECT
    pe.customer_id,
    cg.city,
    cg.country,
    pe.payment_date,
    COUNT(*) AS payment_count,
    SUM(pe.payment_amount) AS day_amount,
    MAX(pe.payment_amount) AS max_payment,
    COUNT(DISTINCT pe.staff_id) AS distinct_staff_count,
    COUNT(DISTINCT pe.staff_store_id) AS distinct_staff_store_count,
    AVG(pe.payment_amount) AS avg_payment_amount,
    SUM(CASE WHEN pe.is_r_rated_or_nc17 = 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS r_or_nc17_payment_share
  FROM pay_enriched pe
  JOIN customer_geo cg ON cg.customer_id = pe.customer_id
  GROUP BY
    pe.customer_id,
    cg.city,
    cg.country,
    pe.payment_date
),
daily_with_hist AS (
  SELECT
    d.*,
    (
      SELECT AVG(d2.day_amount)
      FROM daily d2
      WHERE d2.customer_id = d.customer_id
        AND d2.payment_date >= date(d.payment_date, '-30 days')
        AND d2.payment_date < d.payment_date
    ) AS avg_prev_30d_amount
  FROM daily d
),
qualifying_days AS (
  SELECT
    *
  FROM daily_with_hist
  WHERE avg_prev_30d_amount IS NOT NULL
    AND avg_prev_30d_amount > 0
    AND day_amount >= 3.0 * avg_prev_30d_amount
    AND payment_count >= 3
    AND (distinct_staff_count >= 2 OR distinct_staff_store_count >= 2)
),
ranked AS (
  SELECT
    qd.*,
    RANK() OVER (
      PARTITION BY qd.country
      ORDER BY qd.day_amount DESC
    ) AS day_rank_in_country
  FROM qualifying_days qd
)
SELECT
  customer_id,
  city,
  country,
  payment_date AS suspicious_date,
  payment_count,
  ROUND(day_amount, 2) AS day_amount,
  ROUND(max_payment, 2) AS max_payment,
  ROUND(r_or_nc17_payment_share, 4) AS r_or_nc17_rental_payment_share,
  day_rank_in_country
FROM ranked
ORDER BY
  country,
  day_rank_in_country,
  suspicious_date,
  customer_id;