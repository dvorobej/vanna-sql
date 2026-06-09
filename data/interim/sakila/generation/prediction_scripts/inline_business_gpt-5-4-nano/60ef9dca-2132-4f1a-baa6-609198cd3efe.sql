WITH monthly_customer AS (
  SELECT
    c.h01 AS customer_id,
    c.h03 AS customer_first_name,
    c.h04 AS customer_last_name,
    c.h02 AS store_id,
    strftime('%Y-%m', p.p06) AS month_ym,
    SUM(p.p05) AS monthly_amount,
    COUNT(p.p01) AS payment_count,
    MAX(p.p03) AS last_staff_id
  FROM cus AS c
  JOIN pay AS p
    ON p.p02 = c.h01
  WHERE p.p06 >= '2005-01-01'
    AND p.p06 <  '2006-01-01'
  GROUP BY
    c.h01, c.h03, c.h04, c.h02,
    strftime('%Y-%m', p.p06)
),
monthly_with_personal_avg AS (
  SELECT
    mc.*,
    AVG(mc.monthly_amount) OVER (
      PARTITION BY mc.customer_id
    ) AS personal_avg_monthly_amount
  FROM monthly_customer AS mc
),
monthly_with_store_rank AS (
  SELECT
    mw.*,
    PERCENT_RANK() OVER (
      PARTITION BY mw.store_id, mw.month_ym
      ORDER BY mw.monthly_amount DESC
    ) AS store_month_percent_rank,
    RANK() OVER (
      PARTITION BY mw.store_id, mw.month_ym
      ORDER BY mw.monthly_amount DESC
    ) AS store_month_rank
  FROM monthly_with_personal_avg AS mw
)
SELECT
  mw.customer_id,
  mw.customer_first_name,
  mw.customer_last_name,
  mw.store_id,
  adr.e01 AS address_id,
  cty.d02 AS city_name,
  cnt.c02 AS country_name,
  mw.month_ym AS payment_month,
  ROUND(mw.monthly_amount, 2) AS monthly_payment_amount,
  mw.payment_count,
  ROUND(mw.monthly_amount - mw.personal_avg_monthly_amount, 2) AS deviation_from_personal_avg_amount,
  mw.store_month_rank AS position_in_store_for_month,
  mw.last_staff_id AS last_staff_id
FROM monthly_with_store_rank AS mw
JOIN cus AS c
  ON c.h01 = mw.customer_id
JOIN adr AS adr
  ON adr.e01 = c.h06
JOIN cty AS cty
  ON cty.d01 = adr.e05
JOIN cnt AS cnt
  ON cnt.c01 = cty.d03
WHERE mw.personal_avg_monthly_amount > 0
  AND mw.monthly_amount > mw.personal_avg_monthly_amount * 1.5
  AND mw.store_month_percent_rank <= 0.05
  AND NOT EXISTS (
    SELECT 1
    FROM monthly_with_store_rank AS mw2
    WHERE mw2.customer_id = mw.customer_id
      AND mw2.personal_avg_monthly_amount > 0
      AND mw2.monthly_amount <= mw2.personal_avg_monthly_amount * 1.5
  )
ORDER BY
  mw.month_ym,
  mw.store_id,
  mw.monthly_amount DESC,
  mw.customer_id;