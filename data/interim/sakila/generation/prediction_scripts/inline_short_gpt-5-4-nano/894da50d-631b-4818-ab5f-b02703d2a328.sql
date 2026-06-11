WITH RECURSIVE
months(month_start) AS (
  SELECT date('2000-01-01', 'start of month')
),
payment_by_day AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p05 AS amount,
    date(p.p06, 'start of month') AS month_start,
    p.p06 AS payment_datetime
  FROM pay p
),
payment_with_geo AS (
  SELECT
    pbd.customer_id,
    pbd.month_start,
    pbd.amount,
    pbd.staff_id,
    pbd.payment_id,
    c.h06 AS customer_addr_id,
    cust_cnt.c01 AS customer_store_id_from_citycode,
    cust_country.c02 AS customer_country,
    cust_city.d02 AS customer_city,
    s.o07 AS staff_store_id,
    staff_country.c02 AS staff_country,
    staff_city.d02 AS staff_city,
    pbd.payment_datetime,
    CASE
      WHEN staff_city.d01 IS NOT NULL THEN 1
      ELSE 0
    END AS has_staff_city
  FROM payment_by_day pbd
  JOIN cus c
    ON c.h01 = pbd.customer_id
  JOIN adr cust_adr
    ON cust_adr.e01 = c.h06
  JOIN cty cust_city
    ON cust_city.d01 = cust_adr.e05
  JOIN cnt cust_country
    ON cust_country.c01 = cust_city.d03
  JOIN stf s
    ON s.o01 = pbd.staff_id
  JOIN adr staff_adr
    ON staff_adr.e01 = s.o04
  JOIN cty staff_city
    ON staff_city.d01 = staff_adr.e05
  JOIN cnt staff_country
    ON staff_country.c01 = staff_city.d03
),
monthly_customer AS (
  SELECT
    pwg.customer_id,
    pwg.month_start,
    SUM(pwg.amount) AS month_amount,
    COUNT(*) AS payment_count,
    MAX(pwg.amount) AS max_payment,
    COUNT(DISTINCT pwg.staff_id) AS distinct_staff_count,
    COUNT(DISTINCT pwg.staff_store_id) AS distinct_staff_store_count,
    SUM(
      CASE
        WHEN pwg.staff_city <> pwg.customer_city
          OR pwg.staff_country <> pwg.customer_country
        THEN 1 ELSE 0
      END
    ) * 1.0 / COUNT(*) AS foreign_store_share
  FROM payment_with_geo pwg
  GROUP BY
    pwg.customer_id,
    pwg.month_start
),
monthly_with_history AS (
  SELECT
    mc.*,
    AVG(mc.month_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS avg_prev_month_amount
  FROM monthly_customer mc
),
qualifying_months AS (
  SELECT
    mwh.*
  FROM monthly_with_history mwh
  WHERE mwh.avg_prev_month_amount IS NOT NULL
    AND mwh.payment_count >= 5
    AND mwh.foreign_store_share > 0
    AND mwh.month_amount > 3.0 * mwh.avg_prev_month_amount
    AND mwh.distinct_staff_store_count >= 2
),
payment_month_films AS (
  SELECT DISTINCT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    cat.g02 AS category_name
  FROM pay p
  JOIN ren r
    ON r.q01 = p.p04
  JOIN inv i
    ON i.n01 = r.q03
  JOIN flc fc
    ON fc.l01 = i.n02
  JOIN cat
    ON cat.g01 = fc.l02
),
category_list AS (
  SELECT
    pmf.customer_id,
    pmf.month_start,
    GROUP_CONCAT(DISTINCT pmf.category_name, ', ') AS film_categories
  FROM payment_month_films pmf
  GROUP BY
    pmf.customer_id,
    pmf.month_start
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    ct.d02 AS customer_city,
    cnt.c02 AS customer_country
  FROM cus c
  JOIN adr a
    ON a.e01 = c.h06
  JOIN cty ct
    ON ct.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = ct.d03
)
SELECT
  cm.customer_id,
  cg.customer_country AS customer_country,
  cg.customer_city AS customer_city,
  strftime('%Y-%m', cm.month_start) AS month,
  ROUND(cm.month_amount, 2) AS month_amount,
  cm.payment_count,
  ROUND(cm.foreign_store_share, 4) AS foreign_store_share,
  ROUND(cm.max_payment, 2) AS max_payment,
  RANK() OVER (
    PARTITION BY cm.month_start
    ORDER BY cm.month_amount DESC
  ) AS month_rank,
  cl.film_categories AS film_categories
FROM qualifying_months cm
JOIN customer_geo cg
  ON cg.customer_id = cm.customer_id
LEFT JOIN category_list cl
  ON cl.customer_id = cm.customer_id
 AND cl.month_start = cm.month_start
ORDER BY
  cm.month_start,
  cm.month_amount DESC,
  cm.customer_id;