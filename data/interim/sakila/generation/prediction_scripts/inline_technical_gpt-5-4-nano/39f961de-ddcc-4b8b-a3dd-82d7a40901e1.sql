WITH payment_days AS (
  SELECT
    c.h01 AS customer_id,
    cn.d02 AS city,
    co.c02 AS country,
    date(p.p06) AS payment_date,
    COUNT(*) AS payment_count,
    SUM(CAST(p.p05 AS REAL)) AS day_sum,
    MAX(CAST(p.p05 AS REAL)) AS max_payment,
    COUNT(DISTINCT p.p03) AS distinct_staff_count,
    COUNT(DISTINCT s.j01) AS distinct_store_count
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS i
    ON i.n01 = r.q03
  JOIN sto AS s
    ON s.j01 = i.n03
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS cn
    ON cn.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = cn.d03
  WHERE p.p05 IS NOT NULL
  GROUP BY
    c.h01,
    cn.d02,
    co.c02,
    date(p.p06)
),
daily_with_avg AS (
  SELECT
    pd.*,
    (
      SELECT AVG(pd2.day_sum)
      FROM payment_days pd2
      WHERE pd2.customer_id = pd.customer_id
        AND pd2.payment_date >= date(pd.payment_date, '-30 days')
        AND pd2.payment_date < pd.payment_date
    ) AS avg_prev_30d
  FROM payment_days pd
),
qualified_days AS (
  SELECT
    d.*,
    (d.day_sum / NULLIF(d.avg_prev_30d, 0)) AS ratio_to_avg
  FROM daily_with_avg d
  WHERE d.avg_prev_30d IS NOT NULL
    AND d.payment_count >= 3
    AND d.day_sum >= 3.0 * d.avg_prev_30d
    AND (d.distinct_staff_count >= 2 OR d.distinct_store_count >= 2)
),
horror_ratio AS (
  SELECT
    q.customer_id,
    q.payment_date,
    SUM(CASE WHEN f.i11 IN ('R','NC-17') THEN 1 ELSE 0 END) * 1.0 / q.payment_count AS r_or_nc17_payment_share
  FROM qualified_days q
  JOIN pay p
    ON p.p02 = q.customer_id
   AND date(p.p06) = q.payment_date
  JOIN ren r
    ON r.q01 = p.p04
  JOIN inv i
    ON i.n01 = r.q03
  JOIN flm f
    ON f.i01 = i.n02
  GROUP BY
    q.customer_id,
    q.payment_date,
    q.payment_count
)
SELECT
  q.customer_id,
  q.city AS d02,
  q.country AS c02,
  q.payment_date,
  q.payment_count,
  ROUND(q.day_sum, 2) AS day_sum,
  ROUND(q.max_payment, 2) AS max_payment,
  ROUND(COALESCE(hr.r_or_nc17_payment_share, 0.0), 4) AS r_or_nc17_payment_share,
  RANK() OVER (
    PARTITION BY q.country
    ORDER BY q.day_sum DESC
  ) AS day_rank_in_country
FROM qualified_days q
LEFT JOIN horror_ratio hr
  ON hr.customer_id = q.customer_id
 AND hr.payment_date = q.payment_date
ORDER BY
  q.country,
  day_rank_in_country,
  q.day_sum DESC,
  q.customer_id,
  q.payment_date;