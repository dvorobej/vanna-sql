SELECT AVG(me2.monthly_amount)
      FROM monthly_enriched AS me2
      WHERE me2.customer_id = me.customer_id
        AND me2.payment_month < me.payment_month
        AND me2.payment_month >= strftime('%Y-%m', date(me.payment_month || '-01', '-3 months'))
    ) AS avg_prev_3m_amount,
    (
      SELECT AVG(me2.monthly_payment_count)
      FROM monthly_enriched AS me2
      WHERE me2.customer_id = me.customer_id
        AND me2.payment_month < me.payment_month
        AND me2.payment_month >= strftime('%Y-%m', date(me.payment_month || '-01', '-3 months'))
    ) AS avg_prev_3m_payment_count
  FROM monthly_enriched AS me
),
country_median_amount AS (
  /* медиана суммы по стране в каждом месяце (для SQLite: берём середину при нечётном и среднее двух при чётном) */
  SELECT
    me1.country_name,
    me1.payment_month,
    AVG(me1.monthly_amount) AS country_median_amount
  FROM (
    SELECT
      me.country_name,
      me.payment_month,
      me.monthly_amount,
      ROW_NUMBER() OVER (
        PARTITION BY me.country_name, me.payment_month
        ORDER BY me.monthly_amount
      ) AS rn,
      COUNT(*) OVER (
        PARTITION BY me.country_name, me.payment_month
      ) AS cnt
    FROM monthly_enriched AS me
  ) AS me1
  WHERE me1.rn IN (
    CAST((me1.cnt + 1) / 2 AS INTEGER),
    CAST((me1.cnt + 2) / 2 AS INTEGER)
  )
  GROUP BY
    me1.country_name,
    me1.payment_month
),
country_amount_ranking AS (
  SELECT
    me.customer_id,
    me.payment_month,
    me.country_name,
    me.monthly_amount,
    PERCENT_RANK() OVER (
      PARTITION BY me.country_name, me.payment_month
      ORDER BY me.monthly_amount
    ) AS pct_rank_in_country
  FROM monthly_enriched AS me
),
month_staff_store AS (
  SELECT
    p.p02 AS customer_id,
    strftime('%Y-%m', p.p06) AS payment_month,
    GROUP_CONCAT(DISTINCT (st.o02 || ' ' || st.o03)) AS staff_list,
    GROUP_CONCAT(DISTINCT ('store #' || sto.j01)) AS store_list
  FROM pay AS p
  JOIN stf AS st ON st.o01 = p.p03
  JOIN sto ON sto.j01 = st.o07
  GROUP BY
    p.p02,
    strftime('%Y-%m', p.p06)
)
SELECT
  mhe.customer_id,
  c.h03 AS first_name,
  c.h04 AS last_name,
  mhe.country_name,
  mhe.payment_month,
  ROUND(mhe.monthly_amount, 2) AS monthly_amount,
  mhe.monthly_payment_count,
  ROUND(ch.avg_prev_3m_amount, 2) AS avg_prev_3m_amount,
  ROUND(ch.avg_prev_3m_payment_count, 2) AS avg_prev_3m_payment_count,
  ROUND(cmr.country_median_amount, 2) AS country_median_amount,
  ms.staff_list,
  ms.store_list,
  cr.pct_rank_in_country
FROM customer_history AS ch
JOIN monthly_enriched AS mhe
  ON mhe.customer_id = ch.customer_id
 AND mhe.payment_month = ch.payment_month
LEFT JOIN country_median_amount AS cmr
  ON cmr.country_name = mhe.country_name
 AND cmr.payment_month = mhe.payment_month
JOIN country_amount_ranking AS cr
  ON cr.customer_id = mhe.customer_id
 AND cr.payment_month = mhe.payment_month
LEFT JOIN month_staff_store AS ms
  ON ms.customer_id = mhe.customer_id
 AND ms.payment_month = mhe.payment_month
JOIN cus AS c
  ON c.h01 = mhe.customer_id
WHERE
  ch.avg_prev_3m_amount IS NOT NULL
  AND ch.avg_prev_3m_amount > 0
  AND mhe.monthly_amount >= 3.0 * ch.avg_prev_3m_amount
  AND cmr.country_median_amount IS NOT NULL
  AND cmr.country_median_amount > 0
  AND mhe.monthly_amount >= 2.0 * cmr.country_median_amount
  AND cr.pct_rank_in_country >= 0.95
ORDER BY
  mhe.country_name,
  mhe.payment_month,
  mhe.monthly_amount DESC,
  mhe.customer_id;