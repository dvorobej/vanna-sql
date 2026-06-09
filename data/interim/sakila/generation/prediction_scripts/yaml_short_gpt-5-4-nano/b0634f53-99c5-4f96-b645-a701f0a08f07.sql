WITH payment_details AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p05 AS amount,
    date(p.p06) AS payment_day,
    p.p04 AS rental_id,
    st.o07 AS staff_store_id,
    inv.n03 AS rental_store_id,
    flm.i11 AS rating
  FROM pay AS p
  JOIN stf AS st
    ON st.o01 = p.p03
  LEFT JOIN ren AS r
    ON r.q01 = p.p04
  LEFT JOIN inv
    ON inv.n01 = r.q03
  LEFT JOIN ren AS r2
    ON r2.q01 = p.p04
  LEFT JOIN inv AS inv2
    ON inv2.n01 = r2.q03
  LEFT JOIN stf AS st2
    ON st2.o01 = p.p03
  LEFT JOIN ren AS r3
    ON r3.q01 = p.p04
  LEFT JOIN inv AS inv3
    ON inv3.n01 = r3.q03
  LEFT JOIN pay AS pchk
    ON pchk.p01 = p.p01
  LEFT JOIN ren AS rr
    ON rr.q01 = p.p04
  LEFT JOIN inv AS ii
    ON ii.n01 = rr.q03
  LEFT JOIN stf AS ss
    ON ss.o01 = p.p03
  LEFT JOIN inv AS invx
    ON invx.n01 = rr.q03
  LEFT JOIN inv AS invy
    ON invy.n01 = rr.q03
  LEFT JOIN inv AS invz
    ON invz.n01 = rr.q03
  LEFT JOIN inv AS invw
    ON invw.n01 = rr.q03
  LEFT JOIN inv AS inve
    ON inve.n01 = rr.q03
  LEFT JOIN inv AS invf
    ON invf.n01 = rr.q03
  LEFT JOIN inv AS invg
    ON invg.n01 = rr.q03
  LEFT JOIN inv AS invh
    ON invh.n01 = rr.q03
  LEFT JOIN inv AS invi
    ON invi.n01 = rr.q03
  LEFT JOIN inv AS invj
    ON invj.n01 = rr.q03
  LEFT JOIN flm
    ON flm.i01 = inv3.n02
),
customer_geo AS (
  SELECT
    c.h01 AS customer_id,
    cnt.c01 AS home_country_id
  FROM cus AS c
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty
    ON cty.d01 = a.e05
  JOIN cnt
    ON cnt.c01 = cty.d03
),
day_agg AS (
  SELECT
    pd.customer_id,
    date(pd.payment_day) AS payment_day,
    COUNT(*) AS payment_count,
    SUM(pd.amount) AS day_amount,
    COUNT(DISTINCT pd.staff_id) AS distinct_staff_count,
    COUNT(DISTINCT COALESCE(pd.rental_store_id, pd.staff_store_id)) AS distinct_store_count,
    MAX(pd.staff_store_id) AS any_staff_store_id,
    MAX(pd.rental_store_id) AS any_rental_store_id,
    cg.home_country_id
  FROM payment_details AS pd
  JOIN customer_geo AS cg
    ON cg.customer_id = pd.customer_id
  GROUP BY
    pd.customer_id,
    date(pd.payment_day),
    cg.home_country_id
),
day_scored AS (
  SELECT
    da.*,
    (
      SELECT AVG(daprev.day_amount)
      FROM day_agg AS daprev
      WHERE daprev.customer_id = da.customer_id
        AND daprev.payment_day >= date(da.payment_day, '-30 days')
        AND daprev.payment_day < da.payment_day
    ) AS avg_prev_30d,
    (
      SELECT COUNT(*)
      FROM day_agg AS da2
      WHERE da2.customer_id = da.customer_id
        AND da2.payment_day >= '2005-01-01'
        AND da2.payment_day <= '2005-12-31'
        AND da2.payment_day = da.payment_day
    ) AS dummy
  FROM day_agg AS da
),
suspicious_days AS (
  SELECT
    ds.*,
    CASE
      WHEN ds.avg_prev_30d IS NULL THEN NULL
      WHEN ds.avg_prev_30d = 0 THEN 1
      ELSE ds.day_amount / ds.avg_prev_30d
    END AS exceed_ratio,
    (
      SELECT COUNT(*)
      FROM (
        SELECT
          p2.p02 AS customer_id,
          strftime('%Y-%m', p2.p06) AS m
        FROM pay AS p2
        WHERE p2.p02 = ds.customer_id
          AND date(p2.p06) = ds.payment_day
      ) t
    ) AS dummy2
  FROM day_scored AS ds
  WHERE ds.avg_prev_30d IS NOT NULL
    AND ds.payment_count >= 3
    AND ds.day_amount >= 2 * ds.avg_prev_30d
    AND ds.distinct_staff_count >= 1
    AND ds.distinct_store_count >= 1
),
customer_country_risk AS (
  SELECT
    sd.customer_id,
    sd.payment_day,
    sd.payment_count,
    sd.day_amount,
    sd.exceed_ratio,
    sd.home_country_id,
    RANK() OVER (
      PARTITION BY sd.home_country_id
      ORDER BY sd.exceed_ratio DESC, sd.day_amount DESC, sd.payment_day
    ) AS country_day_rank
  FROM suspicious_days AS sd
)
SELECT
  c.h01 AS customer_id,
  c.h03 || ' ' || c.h04 AS customer_name,
  cnt_home.c02 AS customer_country,
  cty.d02 AS customer_city,
  cdr.payment_day,
  cdr.payment_count,
  ROUND(cdr.day_amount, 2) AS day_amount,
  ROUND(cdr.exceed_ratio, 2) AS exceed_ratio,
  cdr.country_day_rank
FROM customer_country_risk AS cdr
JOIN cus AS c
  ON c.h01 = cdr.customer_id
JOIN adr AS a
  ON a.e01 = c.h06
JOIN cty
  ON cty.d01 = a.e05
JOIN cnt AS cnt_home
  ON cnt_home.c01 = cty.d03
ORDER BY
  customer_country,
  cdr.country_day_rank,
  cdr.payment_day,
  customer_id;