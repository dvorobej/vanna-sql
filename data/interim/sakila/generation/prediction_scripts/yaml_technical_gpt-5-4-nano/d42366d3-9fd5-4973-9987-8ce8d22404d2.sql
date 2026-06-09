WITH base AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p05 AS amount,
    date(p.p06, 'start of month') AS month_start,
    c.h02 AS customer_store_id,
    c.h06 AS customer_address_id,
    a.e05 AS customer_city_id,
    co.c01 AS country_id
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ci
    ON ci.d01 = a.e05
  JOIN cnt AS co
    ON co.c01 = ci.d03
),
monthly_customer AS (
  SELECT
    customer_id,
    customer_store_id,
    country_id,
    month_start,
    COUNT(payment_id) AS payment_count,
    SUM(amount) AS monthly_amount
  FROM base
  GROUP BY
    customer_id, customer_store_id, country_id, month_start
),
monthly_customer_with_windows AS (
  SELECT
    mc.*,
    AVG(monthly_amount) OVER (
      PARTITION BY customer_id
      ORDER BY month_start
      ROWS BETWEEN 2 PRECEDING AND 1 PRECEDING
    ) AS personal_2m_avg_prev
  FROM monthly_customer mc
),
-- подготовим "95-й перцентиль" по сумме для каждой страны и месяца
country_month_amounts AS (
  SELECT
    customer_id,
    country_id,
    month_start,
    monthly_amount
  FROM monthly_customer
),
country_month_ordered AS (
  SELECT
    cma.*,
    ROW_NUMBER() OVER (
      PARTITION BY country_id, month_start
      ORDER BY monthly_amount ASC, customer_id ASC
    ) AS rn,
    COUNT(*) OVER (
      PARTITION BY country_id, month_start
    ) AS n
  FROM country_month_amounts AS cma
),
country_month_p95 AS (
  SELECT
    country_id,
    month_start,
    CASE
      WHEN n = 1 THEN MAX(CASE WHEN rn = 1 THEN monthly_amount END)
      ELSE
        -- линейная интерполяция по позициям
        MAX(CASE WHEN rn = CAST(((0.95 * (n - 1)) ) + 1 AS INTEGER) THEN monthly_amount END)
        + (
          ( (0.95 * (n - 1)) + 1 )
          - CAST(((0.95 * (n - 1)) ) + 1 AS INTEGER)
        )
        * (
          MAX(CASE WHEN rn = CAST(((0.95 * (n - 1)) ) + 1 AS INTEGER) + 1 THEN monthly_amount END)
          - MAX(CASE WHEN rn = CAST(((0.95 * (n - 1)) ) + 1 AS INTEGER) THEN monthly_amount END)
        )
    END AS p95_monthly_amount
  FROM country_month_ordered
  GROUP BY country_id, month_start
),
-- информация по доле "чужих" магазинов и количеству различных сотрудников по месяцам клиента
monthly_staff_mix AS (
  SELECT
    b.customer_id,
    b.country_id,
    b.month_start,
    b.customer_store_id,
    COUNT(b.payment_id) AS total_payments,
    SUM(CASE WHEN st.o07 <> b.customer_store_id THEN 1 ELSE 0 END) AS foreign_store_payments,
    COUNT(DISTINCT b.staff_id) AS distinct_staff_count
  FROM base b
  JOIN stf st
    ON st.o01 = b.staff_id
  GROUP BY
    b.customer_id,
    b.country_id,
    b.month_start,
    b.customer_store_id
),
ranked_by_country_month AS (
  SELECT
    mc.customer_id,
    mc.country_id,
    mc.month_start,
    mc.monthly_amount,
    mc.payment_count,
    RANK() OVER (
      PARTITION BY mc.country_id, mc.month_start
      ORDER BY mc.monthly_amount DESC
    ) AS country_customer_rank,
    cma.n AS country_customer_count
  FROM monthly_customer mc
  JOIN (
    SELECT
      country_id,
      month_start,
      COUNT(*) AS n
    FROM monthly_customer
    GROUP BY country_id, month_start
  ) cma
    ON cma.country_id = mc.country_id
   AND cma.month_start = mc.month_start
)
SELECT
  r.customer_id AS p02,
  r.month_start AS payment_month,
  r.monthly_amount AS monthly_payment_sum,
  r.payment_count AS payment_count,
  r.country_customer_rank,
  r.country_customer_count,
  ROUND(
    1.0 * msm.foreign_store_payments / NULLIF(msm.total_payments, 0),
    4
  ) AS foreign_store_payment_share,
  msm.distinct_staff_count AS distinct_staff_count,
  ROUND(r.monthly_amount - wc.personal_2m_avg_prev, 2) AS deviation_from_personal_2m_avg
FROM ranked_by_country_month r
JOIN monthly_customer_with_windows wc
  ON wc.customer_id = r.customer_id
 AND wc.country_id = r.country_id
 AND wc.month_start = r.month_start
JOIN monthly_staff_mix msm
  ON msm.customer_id = r.customer_id
 AND msm.country_id = r.country_id
 AND msm.month_start = r.month_start
JOIN country_month_p95 p95
  ON p95.country_id = r.country_id
 AND p95.month_start = r.month_start
WHERE wc.personal_2m_avg_prev IS NOT NULL
  AND r.monthly_amount >= 3.0 * wc.personal_2m_avg_prev
  AND r.monthly_amount > p95.p95_monthly_amount
ORDER BY
  r.month_start,
  r.country_id,
  r.country_customer_rank,
  r.customer_id;