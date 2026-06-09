WITH pay_enriched AS (
  SELECT
    p.p01 AS payment_id,
    p.p02 AS customer_id,
    p.p03 AS staff_id,
    p.p04 AS rental_id,
    p.p05 AS payment_amount,
    p.p06 AS payment_ts,
    DATE(p.p06) AS payment_date,
    c.h07 AS customer_active,
    cnt.c02 AS country_name,
    ct.d02 AS city_name,
    s.o07 AS staff_store_id
  FROM pay AS p
  JOIN cus AS c
    ON c.h01 = p.p02
  JOIN adr AS a
    ON a.e01 = c.h06
  JOIN cty AS ct
    ON ct.d01 = a.e05
  JOIN cnt AS cnt
    ON cnt.c01 = ct.d03
  JOIN stf AS s
    ON s.o01 = p.p03
),
joined_films AS (
  SELECT
    pe.*,
    ca.g02 AS category_name,
    f.i02 AS film_title
  FROM pay_enriched AS pe
  LEFT JOIN ren AS r
    ON r.q01 = pe.rental_id
  LEFT JOIN inv AS inv
    ON inv.n01 = r.q03
  LEFT JOIN flm AS f
    ON f.i01 = inv.n02
  LEFT JOIN flc AS fc
    ON fc.l01 = f.i01
  LEFT JOIN cat AS ca
    ON ca.g01 = fc.l02
),
window_base AS (
  SELECT
    jf.*,
    SUM(jf.payment_amount) OVER (
      PARTITION BY jf.customer_id
      ORDER BY jf.payment_ts
      RANGE BETWEEN 6.0 PRECEDING AND CURRENT ROW
    ) AS win_sum_7d,
    COUNT(*) OVER (
      PARTITION BY jf.customer_id
      ORDER BY jf.payment_ts
      RANGE BETWEEN 6.0 PRECEDING AND CURRENT ROW
    ) AS win_cnt_7d,
    AVG(jf_win_hist.avg_sum_hist) OVER (PARTITION BY jf.customer_id) AS dummy
  FROM joined_films AS jf
  LEFT JOIN (
    SELECT 1
  ) AS jf_win_hist
  ON 1 = 1
),
with_history AS (
  SELECT
    wb.*,
    /* Историческое среднее и СКО за предыдущие 30 дней (до текущего платежа) */
    (SELECT AVG(jh.payment_amount) * (SELECT COUNT(*) FROM pay_enriched jh2
      WHERE jh2.customer_id = wb.customer_id
        AND jh2.payment_ts >= datetime(wb.payment_ts, '-30 days')
        AND jh2.payment_ts < wb.payment_ts
    ) ) AS dummy2
  FROM window_base wb
),
suspicious AS (
  SELECT
    wb.payment_id,
    wb.customer_id,
    wb.customer_active,
    wb.payment_date,
    wb.payment_ts,
    wb.win_sum_7d,
    wb.win_cnt_7d
  FROM window_base wb
)
SELECT
  wb.customer_id,
  c.h03 AS customer_first_name,
  c.h04 AS customer_last_name,
  wb.payment_date AS window_end_date,
  wb.win_cnt_7d AS payment_count_7d,
  ROUND(wb.win_sum_7d, 2) AS rolling_sum_7d,

  /* Историческое среднее суммы за 7 дней: берём среднюю сумму rolling_sum_7d по предыдущим 30 дням */
  ROUND((
    SELECT AVG(w2.win_sum_7d)
    FROM (
      SELECT
        p2.p01 AS payment_id2,
        p2.p02 AS customer_id2,
        p2.p06 AS payment_ts2,
        SUM(p2.p05) OVER (
          PARTITION BY p2.p02
          ORDER BY p2.p06
          RANGE BETWEEN 6.0 PRECEDING AND CURRENT ROW
        ) AS win_sum_7d
      FROM pay_enriched p2
      WHERE p2.customer_active = 'Y'
    ) w2
    WHERE w2.customer_id2 = wb.customer_id
      AND w2.payment_ts2 >= datetime(wb.payment_ts, '-30 days')
      AND w2.payment_ts2 < wb.payment_ts
  ), 2) AS avg_sum_prev_30d_for_7d_window,

  wb.win_sum_7d / NULLIF((
    SELECT AVG(w2.win_sum_7d)
    FROM (
      SELECT
        p2.p01 AS payment_id2,
        p2.p02 AS customer_id2,
        p2.p06 AS payment_ts2,
        SUM(p2.p05) OVER (
          PARTITION BY p2.p02
          ORDER BY p2.p06
          RANGE BETWEEN 6.0 PRECEDING AND CURRENT ROW
        ) AS win_sum_7d
      FROM pay_enriched p2
      WHERE p2.customer_active = 'Y'
    ) w2
    WHERE w2.customer_id2 = wb.customer_id
      AND w2.payment_ts2 >= datetime(wb.payment_ts, '-30 days')
      AND w2.payment_ts2 < wb.payment_ts
  ), 0) AS ratio_vs_hist_avg,

  cnt.country_name,
  ct.city_name,

  /* Сотрудники и магазины */
  (SELECT GROUP_CONCAT(DISTINCT CAST(j.s.o01 AS TEXT))
   FROM pay_enriched j
   JOIN stf s ON s.o01 = j.staff_id
   WHERE j.customer_id = wb.customer_id
     AND j.payment_ts >= datetime(wb.payment_ts, '-6 days')
     AND j.payment_ts <= wb.payment_ts
  ) AS staff_ids_in_window,
  (SELECT GROUP_CONCAT(DISTINCT CAST(j.staff_store_id AS TEXT))
   FROM pay_enriched j
   WHERE j.customer_id = wb.customer_id
     AND j.payment_ts >= datetime(wb.payment_ts, '-6 days')
     AND j.payment_ts <= wb.payment_ts
  ) AS store_ids_in_window,

  /* Количество разных арендованных фильмов в окне */
  (SELECT COUNT(DISTINCT i.n02)
   FROM pay_enriched j
   JOIN ren r ON r.q01 = j.rental_id
   JOIN inv i ON i.n01 = r.q03
   WHERE j.customer_id = wb.customer_id
     AND j.payment_ts >= datetime(wb.payment_ts, '-6 days')
     AND j.payment_ts <= wb.payment_ts
  ) AS distinct_rented_films_in_window,

  /* Ранг клиента по сумме подозрительных платежей (за это окно) среди всех клиентов */
  (
    SELECT RANK()
    FROM (
      SELECT
        p3.p02 AS customer_id3,
        SUM(p3.p05) AS sum_7d
      FROM pay p3
      WHERE p3.p06 >= datetime(wb.payment_ts, '-6 days')
        AND p3.p06 <= wb.payment_ts
      GROUP BY p3.p02
    ) rnk
    WHERE rnk.customer_id3 = wb.customer_id
  ) AS suspicious_customer_rank
FROM (
  SELECT
    p.p01,
    p.p02 AS customer_id,
    p.p06 AS payment_ts,
    DATE(p.p06) AS payment_date,
    SUM(p.p05) OVER (
      PARTITION BY p.p02
      ORDER BY p.p06
      RANGE BETWEEN 6.0 PRECEDING AND CURRENT ROW
    ) AS win_sum_7d,
    COUNT(*) OVER (
      PARTITION BY p.p02
      ORDER BY p.p06
      RANGE BETWEEN 6.0 PRECEDING AND CURRENT ROW
    ) AS win_cnt_7d
  FROM pay p
  JOIN cus c ON c.h01 = p.p02
  WHERE c.h07 = 'Y'
) wb
JOIN cus c ON c.h01 = wb.customer_id
JOIN adr a ON a.e01 = c.h06
JOIN cty ct ON ct.d01 = a.e05
JOIN cnt ON cnt.c01 = ct.d03
WHERE
  wb.win_cnt_7d >= 5
  AND wb.win_sum_7d / NULLIF((
    SELECT AVG(w2.win_sum_7d)
    FROM (
      SELECT
        p2.p01 AS payment_id2,
        p2.p02 AS customer_id2,
        p2.p06 AS payment_ts2,
        SUM(p2.p05) OVER (
          PARTITION BY p2.p02
          ORDER BY p2.p06
          RANGE BETWEEN 6.0 PRECEDING AND CURRENT ROW
        ) AS win_sum_7d
      FROM pay p2
      JOIN cus c2 ON c2.h01 = p2.p02
      WHERE c2.h07 = 'Y'
    ) w2
    WHERE w2.customer_id2 = wb.customer_id
      AND w2.payment_ts2 >= datetime(wb.payment_ts, '-30 days')
      AND w2.payment_ts2 < wb.payment_ts
  ), 0) >= 3
ORDER BY
  wb.payment_date,
  wb.win_sum_7d DESC,
  wb.customer_id;