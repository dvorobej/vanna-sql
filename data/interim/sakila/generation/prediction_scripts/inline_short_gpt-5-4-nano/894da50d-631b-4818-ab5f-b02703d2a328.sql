WITH monthly_pay AS (
  SELECT
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    st.o07 AS staff_store_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(p.p05) AS month_amount,
    COUNT(*) AS payment_count,
    MAX(p.p05) AS max_payment,
    COUNT(DISTINCT CASE WHEN st.o07 <> c.h02 THEN st.o07 END) AS other_store_cnt
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN stf AS st
    ON st.o01 = p.p03
  WHERE p.p04 IS NOT NULL
  GROUP BY
    p.p02,
    p.p03,
    st.o07,
    date(p.p06, 'start of month')
),
monthly_customer AS (
  SELECT
    mp.customer_id,
    mp.month_start,
    SUM(mp.month_amount) AS month_amount,
    SUM(mp.payment_count) AS payment_count,
    MAX(mp.max_payment) AS max_payment,
    SUM(CASE WHEN mp.staff_store_id <> (SELECT h02 FROM cus WHERE h01 = mp.customer_id) THEN mp.payment_count ELSE 0 END) AS other_store_payment_count
  FROM monthly_pay AS mp
  GROUP BY
    mp.customer_id,
    mp.month_start
),
monthly_with_avg AS (
  SELECT
    mc.*,
    AVG(mc.month_amount) OVER (
      PARTITION BY mc.customer_id
      ORDER BY mc.month_start
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prev_months_avg_amount
  FROM monthly_customer AS mc
),
month_qualified AS (
  SELECT
    mwa.*
  FROM monthly_with_avg AS mwa
  WHERE mwa.prev_months_avg_amount IS NOT NULL
    AND mwa.month_amount > 3.0 * mwa.prev_months_avg_amount
    AND mwa.payment_count >= 5
),
month_ranked AS (
  SELECT
    mq.*,
    RANK() OVER (
      PARTITION BY mq.month_start
      ORDER BY mq.month_amount DESC
    ) AS month_rank
  FROM month_qualified AS mq
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    c.h02 AS customer_store_id,
    cty_c.d02 AS customer_city,
    cnt_c.c02 AS customer_country
  FROM cus AS c
  JOIN adr AS a_c
    ON a_c.e01 = c.h06
  JOIN cty AS cty_c
    ON cty_c.d01 = a_c.e05
  JOIN cnt AS cnt_c
    ON cnt_c.c01 = cty_c.d03
),
monthly_store_geo AS (
  SELECT
    p.p02 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    SUM(p.p05) AS month_amount_from_staff_store,
    COUNT(*) AS payment_count_from_staff_store,
    st.o07 AS staff_store_id
  FROM pay AS p
  JOIN stf AS st
    ON st.o01 = p.p03
  WHERE p.p04 IS NOT NULL
  GROUP BY
    p.p02,
    date(p.p06, 'start of month'),
    st.o07
),
foreign_store_share AS (
  SELECT
    msg.customer_id,
    msg.month_start,
    SUM(
      CASE
        WHEN sg.staff_city <> cg.customer_city OR sg.staff_country <> cg.customer_country
          THEN msg.payment_count_from_staff_store
        ELSE 0
      END
    ) AS foreign_payment_count,
    SUM(msg.payment_count_from_staff_store) AS total_payment_count
  FROM monthly_store_geo AS msg
  JOIN customer_geo AS cg
    ON cg.customer_id = msg.customer_id
  JOIN sto AS sg_sto
    ON sg_sto.j01 = msg.staff_store_id
  JOIN adr AS sg_a
    ON sg_a.e01 = sg_sto.j02
  JOIN cty AS sg_city
    ON sg_city.d01 = sg_a.e05
  JOIN cnt AS sg_country
    ON sg_country.c01 = sg_city.d03
  JOIN (
    SELECT
      cty.d01,
      cty.d02 AS staff_city,
      cnt.c02 AS staff_country
    FROM cty
    JOIN cnt ON cnt.c01 = cty.d03
  ) AS sg
    ON sg.d01 = sg_city.d01
  GROUP BY
    msg.customer_id,
    msg.month_start
),
month_categories AS (
  SELECT
    c.h01 AS customer_id,
    date(p.p06, 'start of month') AS month_start,
    group_concat(DISTINCT cat.g02, ', ') AS categories
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN ren AS r
    ON r.q01 = p.p04
  JOIN inv AS i
    ON i.n01 = r.q03
  JOIN flc AS l
    ON l.l01 = i.n02
  JOIN cat
    ON cat.g01 = l.l02
  WHERE p.p04 IS NOT NULL
  GROUP BY
    c.h01,
    date(p.p06, 'start of month')
)
SELECT
  mrq.customer_id,
  cg.customer_country,
  cg.customer_city,
  strftime('%Y-%m', mrq.month_start) AS month,
  ROUND(mrq.month_amount, 2) AS month_amount,
  mrq.payment_count,
  ROUND(1.0 * fss.foreign_payment_count / NULLIF(fss.total_payment_count, 0), 4) AS foreign_store_share,
  ROUND(mrq.max_payment, 2) AS max_payment,
  mrq.month_rank,
  mc.categories AS film_categories
FROM month_ranked AS mrq
JOIN customer_geo AS cg
  ON cg.customer_id = mrq.customer_id
JOIN foreign_store_share AS fss
  ON fss.customer_id = mrq.customer_id
 AND fss.month_start = mrq.month_start
LEFT JOIN month_categories AS mc
  ON mc.customer_id = mrq.customer_id
 AND mc.month_start = mrq.month_start
ORDER BY
  mrq.month_start,
  mrq.month_rank,
  mrq.customer_id;