WITH daily AS (
  SELECT
    c.h01 AS customer_id,
    c.h03,
    c.h04,
    c.h02 AS store_id,
    cnt.c02 AS country,
    cty.d02 AS city,
    DATE(p.p06) AS day_date,
    COUNT(*) AS payment_count,
    SUM(p.p05) AS day_amount
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty
    ON cty.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = cty.d03
  GROUP BY
    c.h01, c.h03, c.h04, c.h02,
    cnt.c02, cty.d02,
    DATE(p.p06)
),
with_personal_avg AS (
  SELECT
    d.*,
    (
      SELECT AVG(d2.day_amount)
      FROM daily AS d2
      WHERE d2.customer_id = d.customer_id
        AND d2.day_date >= date(d.day_date, '-30 day')
        AND d2.day_date < d.day_date
    ) AS avg_prev_30d
  FROM daily AS d
),
country_p95 AS (
  -- п95 по дневным суммам клиентов внутри страны: используем эмпирический порог по рангу
  SELECT
    country,
    day_amount,
    ROW_NUMBER() OVER (PARTITION BY country ORDER BY day_amount DESC) AS rn_desc,
    COUNT(*) OVER (PARTITION BY country) AS cnt_days
  FROM daily
),
p95_threshold AS (
  SELECT
    country,
    MIN(day_amount) AS p95_day_amount
  FROM country_p95
  WHERE rn_desc <= CAST(CEIL(cnt_days * 0.05) AS INTEGER)
  GROUP BY country
),
scored AS (
  SELECT
    w.*,
    (w.day_amount - w.avg_prev_30d) AS deviation_from_personal_avg,
    (w.day_amount / NULLIF(w.avg_prev_30d, 0)) AS spike_ratio,
    p.p95_day_amount
  FROM with_personal_avg AS w
  JOIN p95_threshold AS p
    ON p.country = w.country
  WHERE w.avg_prev_30d IS NOT NULL
)
SELECT
  s.customer_id,
  s.h03,
  s.h04,
  s.country AS cnt_c02,
  s.city AS cty_d02,
  s.store_id AS cus_h02,
  s.day_date AS spike_date,
  s.payment_count,
  ROUND(s.day_amount, 2) AS day_amount,
  ROUND(s.avg_prev_30d, 2) AS avg_prev_30d,
  ROUND(s.deviation_from_personal_avg, 2) AS deviation_from_personal_avg,
  RANK() OVER (
    PARTITION BY s.country
    ORDER BY s.day_amount DESC, s.customer_id
  ) AS rank_in_country_by_spike
FROM scored AS s
WHERE s.avg_prev_30d > 0
  AND s.day_amount >= 3 * s.avg_prev_30d
  AND s.day_amount > s.p95_day_amount
ORDER BY
  s.country,
  rank_in_country_by_spike,
  s.day_amount DESC,
  s.customer_id,
  s.day_date;