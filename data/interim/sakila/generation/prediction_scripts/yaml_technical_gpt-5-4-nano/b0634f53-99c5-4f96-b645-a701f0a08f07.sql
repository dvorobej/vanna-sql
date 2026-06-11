SELECT ct2.d03
                       FROM adr AS a2
                       JOIN cty AS ct2 ON ct2.d01 = a2.e05
                       WHERE a2.e01 = st.j03
                       LIMIT 1)
  LEFT JOIN stf AS s
    ON s.o01 = p.p03
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    p.p02,
    date(p.p06),
    ccountry.c01
),
daily_with_avg AS (
  SELECT
    d.*,
    (
      SELECT AVG(d2.day_amount)
      FROM daily AS d2
      WHERE d2.customer_id = d.customer_id
        AND d2.payment_day >= date(d.payment_day, '-30 day')
        AND d2.payment_day < d.payment_day
    ) AS avg_day_amount_prev_30d,
    (
      SELECT group_concat(DISTINCT cstore2.country_id)
      FROM pay AS p2
      LEFT JOIN ren AS r2 ON r2.q01 = p2.p04
      LEFT JOIN inv AS i2 ON i2.n01 = r2.q03
      LEFT JOIN sto AS st2 ON st2.j01 = i2.n03
      LEFT JOIN (
        SELECT
          st_inner.j01,
          ct_inner.d03 AS country_id
        FROM sto AS st_inner
        JOIN adr AS a_inner ON a_inner.e01 = st_inner.j03
        JOIN cty AS ct_inner ON ct_inner.d01 = a_inner.e05
      ) AS cstore2
        ON cstore2.j01 = st2.j01
      WHERE p2.p02 = d.customer_id
        AND date(p2.p06) = d.payment_day
    ) AS store_countries
  FROM daily AS d
)
SELECT
  d.customer_id AS h01_customer_id,
  c.h03 || ' ' || c.h04 AS customer_name,
  cntc.c02 AS customer_country,
  d.payment_day,
  d.payment_count,
  ROUND(d.day_amount, 2) AS day_amount,
  ROUND(d.avg_day_amount_prev_30d, 2) AS avg_day_amount_prev_30d,
  d.distinct_staff_count,
  d.distinct_store_count,
  d.store_countries AS store_countries,
  RANK() OVER (
    PARTITION BY cntc.c01
    ORDER BY (d.day_amount / NULLIF(d.avg_day_amount_prev_30d, 0)) DESC,
             d.day_amount DESC
  ) AS suspicion_rank_in_country
FROM daily_with_avg AS d
JOIN cus AS c
  ON c.h01 = d.customer_id
JOIN adr AS a
  ON a.e01 = c.h06
JOIN cty AS cc
  ON cc.d01 = a.e05
JOIN cnt AS cntc
  ON cntc.c01 = cc.d03
WHERE d.payment_count >= 3
  AND d.avg_day_amount_prev_30d IS NOT NULL
  AND d.avg_day_amount_prev_30d > 0
  AND d.day_amount >= 2.0 * d.avg_day_amount_prev_30d
  AND d.payments_through_other_country_count >= 1
ORDER BY
  customer_country,
  suspicion_rank_in_country,
  d.payment_day,
  d.customer_id;