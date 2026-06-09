SELECT l01, l02
    FROM flc
  ) fca
    ON fca.l01 = flm.i01
  WHERE pb.payment_date IN (SELECT payment_date FROM suspicious_windows)
    AND pb.customer_id IN (SELECT customer_id FROM suspicious_windows)
  GROUP BY pb.customer_id, pb.payment_date
),
window_films_count AS (
  SELECT
    pb.customer_id,
    pw.payment_date,
    COUNT(DISTINCT i.n02) AS distinct_films_in_window
  FROM payments_base pb
  JOIN suspicious_windows pw
    ON pw.customer_id = pb.customer_id
   AND pb.payment_date BETWEEN date(pw.payment_date, '-6 day') AND pw.payment_date
  LEFT JOIN ren r ON r.q01 = pb.rental_id
  LEFT JOIN inv i ON i.n01 = r.q03
  GROUP BY pb.customer_id, pw.payment_date
),
window_staff_list AS (
  SELECT
    pb.customer_id,
    pw.payment_date,
    GROUP_CONCAT(DISTINCT s.o02 || ' ' || s.o03) AS staff_names
  FROM payments_base pb
  JOIN suspicious_windows pw
    ON pw.customer_id = pb.customer_id
   AND pb.payment_date BETWEEN date(pw.payment_date, '-6 day') AND pw.payment_date
  JOIN stf s ON s.o01 = pb.staff_id
  GROUP BY pb.customer_id, pw.payment_date
),
window_store_list AS (
  SELECT
    pb.customer_id,
    pw.payment_date,
    GROUP_CONCAT(DISTINCT st.j01 || ':' || st.j02) AS store_list
  FROM payments_base pb
  JOIN suspicious_windows pw
    ON pw.customer_id = pb.customer_id
   AND pb.payment_date BETWEEN date(pw.payment_date, '-6 day') AND pw.payment_date
  LEFT JOIN ren r ON r.q01 = pb.rental_id
  LEFT JOIN inv i ON i.n01 = r.q03
  LEFT JOIN sto st ON st.j01 = i.n03
  GROUP BY pb.customer_id, pw.payment_date
),
suspicious_rank AS (
  SELECT
    sw.*,
    RANK() OVER (ORDER BY sw.win_sum_7d DESC) AS suspicious_client_amount_rank
  FROM suspicious_windows sw
)
SELECT
  sr.customer_id,
  pg.customer_name,
  pg.country_name,
  pg.city_name,
  sr.payment_date AS window_end_date,
  sr.win_cnt_7d AS payment_count_7d,
  ROUND(sr.win_sum_7d, 2) AS payment_sum_7d,
  ROUND(sr.win_sum_7d / NULLIF(sr.win_cnt_7d, 0), 4) AS avg_payment_amount_7d,
  wsl.distinct_films_in_window AS distinct_films_in_window,
  ws.staff_names AS staff_names_in_window,
  wst.store_list AS stores_in_window,
  sr.suspicious_client_amount_rank AS client_amount_rank
FROM suspicious_rank sr
JOIN payment_geo pg ON pg.customer_id = sr.customer_id
LEFT JOIN window_films_count wsl
  ON wsl.customer_id = sr.customer_id
 AND wsl.payment_date = sr.payment_date
LEFT JOIN window_staff_list ws
  ON ws.customer_id = sr.customer_id
 AND ws.payment_date = sr.payment_date
LEFT JOIN window_store_list wst
  ON wst.customer_id = sr.customer_id
 AND wst.payment_date = sr.payment_date
ORDER BY
  sr.win_sum_7d DESC,
  sr.customer_id,
  sr.payment_date;