SELECT 1 AS dummy
  ) d
  WHERE ca.g02 IN ('Action','New')
  GROUP BY
    cn.c01,
    cn.c02,
    ct.d01,
    ct.d02,
    sbst.o07,
    strftime('%Y-%m', p.p06)
),
ranked AS (
  SELECT
    pg.*,
    cs.action_sum,
    cs.new_sum,
    (cs.action_sum / NULLIF(pg.payment_sum, 0.0)) AS action_share,
    (cs.new_sum / NULLIF(pg.payment_sum, 0.0)) AS new_share,
    RANK() OVER (
      PARTITION BY pg.country_id, pg.payment_month
      ORDER BY pg.payment_sum DESC
    ) AS country_month_rank
  FROM payments_grouped pg
  LEFT JOIN category_share cs
    ON cs.country_id = pg.country_id
   AND cs.city_id = pg.city_id
   AND cs.store_id = pg.store_id
   AND cs.payment_month = pg.payment_month
)
SELECT
  country_name,
  city_name,
  store_id,
  payment_month,
  ROUND(payment_sum, 2) AS payment_sum,
  payment_count,
  ROUND(max_payment, 2) AS max_payment,
  ROUND(COALESCE(action_share, 0.0), 4) AS action_share,
  ROUND(COALESCE(new_share, 0.0), 4) AS new_share,
  country_month_rank
FROM ranked
ORDER BY
  payment_month,
  country_name,
  country_month_rank,
  payment_sum DESC,
  store_id;