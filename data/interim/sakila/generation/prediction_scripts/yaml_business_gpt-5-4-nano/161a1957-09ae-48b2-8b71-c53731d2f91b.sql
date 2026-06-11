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
daily_payments AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06) AS payment_date,
    SUM(CAST(p.p05 AS REAL)) AS day_amount,
    COUNT(*) AS payment_count,
    COUNT(DISTINCT p.p03) AS staff_count,
    COUNT(DISTINCT s.o07) AS store_count
  FROM pay AS p
  JOIN stf AS s ON s.o01 = p.p03
  GROUP BY
    p.p02,
    date(p.p06)
),
daily_with_personal_avg AS (
  SELECT
    dp.*,
    (
      SELECT AVG(dp2.day_amount)
      FROM daily_payments AS dp2
      WHERE dp2.customer_id = dp.customer_id
        AND dp2.payment_date >= date(dp.payment_date, '-30 days')
        AND dp2.payment_date < dp.payment_date
    ) AS personal_avg_30d
  FROM daily_payments AS dp
),
country_day_ranked AS (
  SELECT
    dw.customer_id,
    cg.country,
    dw.payment_date,
    dw.day_amount,
    PERCENT_RANK() OVER (
      PARTITION BY cg.country, dw.payment_date
      ORDER BY dw.day_amount
    ) AS pr,
    RANK() OVER (
      PARTITION BY cg.country, dw.payment_date
      ORDER BY dw.day_amount
    ) AS day_amount_rank_in_country
  FROM daily_with_personal_avg AS dw
  JOIN customer_geo AS cg ON cg.customer_id = dw.customer_id
),
country_daily_percentiles AS (
  SELECT
    cg.country_id,
    cg.country,
    dw.payment_date,
    dw.day_amount,
    (
      SELECT AVG(x.day_amount)
      FROM (
        SELECT
          d2.day_amount,
          NTILE(100) OVER (
            PARTITION BY cg2.country, d2.payment_date
            ORDER BY d2.day_amount
          ) AS tile100
        FROM daily_payments AS d2
        JOIN customer_geo AS cg2 ON cg2.customer_id = d2.customer_id
        WHERE cg2.country = cg.country
      ) AS x
    ) AS p95_dummy
  FROM daily_with_personal_avg dw
  JOIN customer_geo cg ON cg.customer_id = dw.customer_id
  LIMIT 0
),
daily_with_country_p95 AS (
  SELECT
    dw.*,
    cg.country,
    (
      SELECT dd2.day_amount
      FROM (
        SELECT
          dp2.day_amount,
          ROW_NUMBER() OVER (
            PARTITION BY cg2.country, dp2.payment_date
            ORDER BY dp2.day_amount DESC
          ) AS rn,
          COUNT(*) OVER (
            PARTITION BY cg2.country, dp2.payment_date
          ) AS cnt
        FROM daily_payments AS dp2
        JOIN customer_geo AS cg2 ON cg2.customer_id = dp2.customer_id
        WHERE cg2.country = cg.country
          AND dp2.payment_date = dw.payment_date
      ) AS ranked
      WHERE rn = CAST(CEIL(0.05 * cnt) AS INTEGER)
    ) AS p95_country_daily_amount
  FROM daily_with_personal_avg dw
  JOIN customer_geo cg ON cg.customer_id = dw.customer_id
)
SELECT
  dwc.customer_id,
  cg.first_name,
  cg.last_name,
  cg.country,
  cg.city,
  dwc.payment_date,
  dwc.payment_count,
  ROUND(dwc.day_amount, 2) AS day_amount,
  dwc.staff_count,
  dwc.store_count,
  ROUND(dwc.personal_avg_30d, 2) AS personal_avg_30d,
  ROUND(dwc.day_amount - dwc.personal_avg_30d, 2) AS deviation_from_personal_avg,
  DENSE_RANK() OVER (
    PARTITION BY cg.country
    ORDER BY (dwc.day_amount - dwc.personal_avg_30d) DESC, dwc.day_amount DESC
  ) AS suspicious_rank_in_country,
  (
    SELECT GROUP_CONCAT(DISTINCT p3.p03)
    FROM pay AS p3
    WHERE p3.p02 = dwc.customer_id
      AND date(p3.p06) = dwc.payment_date
  ) AS staff_id_list
FROM daily_with_country_p95 AS dwc
JOIN customer_geo cg ON cg.customer_id = dwc.customer_id
WHERE dwc.personal_avg_30d IS NOT NULL
  AND dwc.personal_avg_30d > 0
  AND dwc.payment_count >= 3
  AND dwc.staff_count >= 2
  AND dwc.day_amount > 2.0 * dwc.personal_avg_30d
  AND dwc.p95_country_daily_amount IS NOT NULL
  AND dwc.day_amount > dwc.p95_country_daily_amount
ORDER BY
  cg.country,
  suspicious_rank_in_country,
  dwc.payment_date,
  dwc.day_amount DESC,
  dwc.customer_id;