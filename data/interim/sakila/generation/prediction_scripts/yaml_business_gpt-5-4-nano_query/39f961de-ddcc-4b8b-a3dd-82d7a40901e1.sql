WITH customer_geo AS (
  SELECT
    cus.h01 AS customer_id,
    cus.h03 AS first_name,
    cus.h04 AS last_name,
    cnt.c02 AS country,
    cty.d02 AS city,
    cus.h02 AS registration_store_id
  FROM cus
  JOIN adr ON adr.e01 = cus.h06
  JOIN cty ON cty.d01 = adr.e05
  JOIN cnt ON cnt.c01 = cty.d03
),
payments_daily AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS pay_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS daily_sum,
    MAX(CAST(p.p05 AS REAL)) AS max_payment,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT COALESCE(st.o07, -1))) AS distinct_store_count,
    SUM(CASE
          WHEN ca.g02 IS NOT NULL AND (ca_rating.i11 IN ('R','NC-17')) THEN 1
          ELSE 0
        END) AS r_or_nc17_payment_count,
    SUM(CASE
          WHEN ca_rating.i11 IN ('R','NC-17') THEN CAST(p.p05 AS REAL)
          ELSE 0
        END) AS r_or_nc17_payment_amount
  FROM pay p
  JOIN customer_geo cg ON cg.customer_id = p.p02
  LEFT JOIN stf st ON st.o01 = p.p03
  LEFT JOIN ren r ON r.q01 = p.p04
  LEFT JOIN inv iinv ON iinv.n01 = r.q03
  LEFT JOIN flm ca_rating ON ca_rating.i01 = iinv.n02
  LEFT JOIN flc fc ON fc.l01 = iinv.n02
  LEFT JOIN cat ca ON ca.g01 = fc.l02
  GROUP BY p.p02, date(p.p06)
),
daily_with_prev_avg AS (
  SELECT
    pd.*,
    (
      SELECT AVG(pd2.daily_sum)
      FROM payments_daily pd2
      WHERE pd2.customer_id = pd.customer_id
        AND pd2.pay_date >= date(pd.pay_date, '-30 days')
        AND pd2.pay_date < pd.pay_date
    ) AS avg_prev_30d
  FROM payments_daily pd
),
qualified_days AS (
  SELECT
    dwp.*,
    (CAST(r_or_nc17_payment_amount AS REAL) / NULLIF(daily_sum, 0)) AS r_or_nc17_share_amount,
    (daily_sum / NULLIF(avg_prev_30d, 0)) AS ratio_to_avg
  FROM daily_with_prev_avg dwp
  WHERE avg_prev_30d IS NOT NULL
    AND avg_prev_30d > 0
    AND payment_count >= 3
    AND daily_sum >= 3 * avg_prev_30d
    AND (distinct_staff_count >= 2 OR distinct_store_count >= 2)
),
ranked AS (
  SELECT
    qd.*,
    DENSE_RANK() OVER (
      PARTITION BY customer_id
      ORDER BY daily_sum DESC
    ) AS day_rank_within_customer
  FROM qualified_days qd
),
final AS (
  SELECT
    r.customer_id,
    cg.city,
    cg.country,
    r.pay_date AS suspicious_date,
    r.payment_count,
    ROUND(r.daily_sum, 2) AS daily_sum,
    ROUND(r.max_payment, 2) AS max_payment,
    ROUND(r.r_or_nc17_share_amount, 4) AS r_or_nc17_lease_share,
    DENSE_RANK() OVER (
      PARTITION BY cg.country
      ORDER BY r.daily_sum DESC
    ) AS country_day_rank
  FROM ranked r
  JOIN customer_geo cg ON cg.customer_id = r.customer_id
)
SELECT
  customer_id,
  city,
  country,
  suspicious_date,
  payment_count,
  daily_sum,
  max_payment,
  r_or_nc17_lease_share,
  country_day_rank
FROM final
ORDER BY country, country_day_rank, suspicious_date, customer_id;