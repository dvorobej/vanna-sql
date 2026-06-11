SELECT AVG(d2.day_amount)
      FROM daily AS d2
      WHERE d2.customer_id = d.customer_id
        AND d2.payment_day >= DATE(d.payment_day, '-30 day')
        AND d2.payment_day <  d.payment_day
    ), 0.0) AS avg_prev_30d
  FROM daily AS d
),
qualifying_days AS (
  SELECT
    dp.*
    , (CASE WHEN dp.avg_prev_30d > 0 THEN dp.day_amount / dp.avg_prev_30d ELSE NULL END) AS exceed_ratio
  FROM daily_prev_avg AS dp
  WHERE dp.payment_count >= 3
    AND dp.avg_prev_30d > 0
    AND dp.day_amount >= 2.0 * dp.avg_prev_30d
),
store_countries_for_day AS (
  SELECT
    q.customer_id,
    q.payment_day,
    GROUP_CONCAT(DISTINCT cnt_store.c02) AS store_countries_list,
    SUM(CASE WHEN cnt_store.c01 <> cg.customer_country_id THEN 1 ELSE 0 END) AS cross_country_store_count
  FROM qualifying_days AS q
  JOIN pay AS p
    ON p.p02 = q.customer_id
   AND DATE(p.p06) = q.payment_day
  JOIN stf AS s
    ON s.o01 = p.p03
  JOIN sto AS st
    ON st.j01 = s.o07
  JOIN adr AS a_st
    ON a_st.e01 = st.j03
  JOIN cty AS cy_st
    ON cy_st.d01 = a_st.e05
  JOIN cnt AS cnt_store
    ON cnt_store.c01 = cy_st.d03
  JOIN customer_geo AS cg
    ON cg.customer_id = q.customer_id
  GROUP BY
    q.customer_id,
    q.payment_day
),
final AS (
  SELECT
    q.customer_id,
    cg.customer_country_name AS customer_country,
    q.payment_day,
    q.payment_count,
    ROUND(q.day_amount, 2) AS day_amount,
    ROUND(q.avg_prev_30d, 2) AS avg_prev_30d,
    q.distinct_staff_count,
    q.distinct_store_count,
    sc.store_countries_list,
    (q.day_amount - q.avg_prev_30d) AS deviation_from_avg,
    RANK() OVER (
      PARTITION BY cg.customer_country_id
      ORDER BY (q.day_amount / q.avg_prev_30d) DESC, q.day_amount DESC, q.customer_id
    ) AS suspicious_rank_in_country
  FROM qualifying_days AS q
  JOIN customer_geo AS cg
    ON cg.customer_id = q.customer_id
  JOIN store_countries_for_day AS sc
    ON sc.customer_id = q.customer_id
   AND sc.payment_day = q.payment_day
  WHERE sc.cross_country_store_count > 0
)
SELECT
  customer_id,
  customer_country,
  payment_day,
  payment_count,
  day_amount,
  avg_prev_30d,
  distinct_staff_count,
  distinct_store_count,
  store_countries_list,
  ROUND(deviation_from_avg, 2) AS deviation_from_avg,
  suspicious_rank_in_country
FROM final
ORDER BY
  customer_country,
  suspicious_rank_in_country,
  payment_day,
  customer_id;