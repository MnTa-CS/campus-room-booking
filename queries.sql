-- =====================================================================
--  CAMPUS ROOM BOOKING SYSTEM  -  important queries (Q1 - Q13)
--  Run AFTER campus_room_booking.sql. Select the database first:
--      USE campus_room_booking;
--
--  Each query that needs input values uses a session variable such as
--  @date so you can run it as-is in phpMyAdmin / Workbench.
--  In PHP (PDO) replace  @date  with a named placeholder  :date  and
--  pass the value with $stmt->execute([':date' => $date]).
--  NEVER build the SQL by joining strings with user input.
-- =====================================================================
USE campus_room_booking;

-- ---------------------------------------------------------------------
-- Q1. All rooms with building, floor, type, capacity
--     Feature: room list.  PHP supplies: nothing.
--     Relational algebra: rooms JOIN buildings, then PROJECT 5 columns.
-- ---------------------------------------------------------------------
SELECT r.room_id, r.room_name, b.building_name, r.floor, r.room_type, r.capacity
FROM rooms r
JOIN buildings b ON b.building_id = r.building_id
ORDER BY b.building_name, r.floor, r.room_name;

-- ---------------------------------------------------------------------
-- Q2. Facilities in each room (one line per room, facilities joined)
--     Feature: room details page.  PHP supplies: nothing
--     (add  WHERE r.room_id = :room_id  for a single room).
--     LEFT JOIN keeps rooms that have no facilities at all.
-- ---------------------------------------------------------------------
SELECT r.room_id, r.room_name,
       COALESCE(GROUP_CONCAT(f.facility_name ORDER BY f.facility_name SEPARATOR ', '),
                '(none)') AS facilities
FROM rooms r
LEFT JOIN room_facilities rf ON rf.room_id = r.room_id
LEFT JOIN facilities f       ON f.facility_id = rf.facility_id
GROUP BY r.room_id, r.room_name
ORDER BY r.room_id;

-- ---------------------------------------------------------------------
-- Q3. Rooms AVAILABLE for a date + time range (and enough capacity)
--     Feature: availability search.
--     PHP supplies: :date, :start_time, :end_time, :attendees
--     A room is available when NO Approved booking overlaps the slot.
--     Pending bookings do not block (brief rule).
-- ---------------------------------------------------------------------
SET @date = CURDATE() + INTERVAL 1 DAY;
SET @start_time = '10:00:00';
SET @end_time   = '11:00:00';
SET @attendees  = 4;

SELECT r.room_id, r.room_name, b.building_name, r.room_type, r.capacity
FROM rooms r
JOIN buildings b ON b.building_id = r.building_id
WHERE r.capacity >= @attendees
  AND NOT EXISTS (
        SELECT 1
        FROM bookings bk
        WHERE bk.room_id      = r.room_id
          AND bk.booking_date = @date
          AND bk.status       = 'Approved'
          AND bk.start_time   < @end_time      -- overlap test
          AND bk.end_time     > @start_time)
ORDER BY b.building_name, r.room_name;
-- With the sample data, Study Room L1 is NOT listed (Approved 09:00-11:00).

-- Q3b. Same search but showing every room as 'Free' or 'Booked'
SELECT r.room_id, r.room_name,
       CASE WHEN EXISTS (
              SELECT 1 FROM bookings bk
              WHERE bk.room_id = r.room_id AND bk.booking_date = @date
                AND bk.status = 'Approved'
                AND bk.start_time < @end_time AND bk.end_time > @start_time)
            THEN 'Booked' ELSE 'Free' END AS availability
FROM rooms r
ORDER BY r.room_id;

-- ---------------------------------------------------------------------
-- Q4. Insert a NEW pending booking request
--     Feature: booking form.
--     PHP supplies: :user_id (from the login session), :room_id,
--       :booking_date, :start_time, :end_time, :purpose, :attendee_count
--     status/created_at are filled by the database defaults (Pending).
--     The triggers + CHECKs reject bad times or too many attendees.
-- ---------------------------------------------------------------------
SET @user_id = 4;  SET @room_id = 2;
SET @booking_date = CURDATE() + INTERVAL 5 DAY;
SET @purpose = 'Presentation rehearsal';  SET @attendee_count = 4;

INSERT INTO bookings (user_id, room_id, booking_date, start_time, end_time, purpose, attendee_count)
VALUES (@user_id, @room_id, @booking_date, '14:00:00', '15:30:00', @purpose, @attendee_count);
-- PHP: $pdo->lastInsertId() returns the new booking_id.

-- ---------------------------------------------------------------------
-- Q5. A user's own bookings + status
--     Feature: "My bookings".  PHP supplies: :user_id (from session)
-- ---------------------------------------------------------------------
SET @user_id = 4;
SELECT bk.booking_id, r.room_name, b.building_name, bk.booking_date,
       bk.start_time, bk.end_time, bk.purpose, bk.attendee_count, bk.status
FROM bookings bk
JOIN rooms r     ON r.room_id = bk.room_id
JOIN buildings b ON b.building_id = r.building_id
WHERE bk.user_id = @user_id
ORDER BY bk.booking_date DESC, bk.start_time;

-- ---------------------------------------------------------------------
-- Q6. Pending requests for an administrator to review (oldest first)
--     Feature: admin review page.  PHP supplies: nothing
--     (admin-only page: check the session role in PHP).
--     'competing_approved' flags requests that ALREADY clash with an
--     Approved booking, so the admin knows approval will fail.
-- ---------------------------------------------------------------------
SELECT bk.booking_id, u.full_name AS requester, u.department,
       r.room_name, bk.booking_date, bk.start_time, bk.end_time,
       bk.attendee_count, r.capacity, bk.purpose, bk.created_at,
       (SELECT COUNT(*) FROM bookings a
         WHERE a.room_id = bk.room_id AND a.booking_date = bk.booking_date
           AND a.status = 'Approved'
           AND a.start_time < bk.end_time AND a.end_time > bk.start_time) AS competing_approved
FROM bookings bk
JOIN users u ON u.user_id = bk.user_id
JOIN rooms r ON r.room_id = bk.room_id
WHERE bk.status = 'Pending'
ORDER BY bk.created_at, bk.booking_id;

-- ---------------------------------------------------------------------
-- Q7. APPROVE a booking (with conflict check) - uses the transaction
--     procedure. Feature: admin "Approve" button.
--     PHP supplies: :booking_id, :admin_id (from session, role checked)
--     Success: no error. Conflict: error 1644 / SQLSTATE 45000 with the
--     message "Conflict: room already has an Approved booking ..."
--     PHP: catch PDOException, show $e->getMessage() to the admin.
-- ---------------------------------------------------------------------
-- CALL sp_approve_booking(3, 1);     -- try it: booking #3 is back-to-back with #1, so it succeeds
-- CALL sp_approve_booking(2, 1);     -- fails (#2 overlaps the Approved #1)
-- (see test_conflict.sql for the full tested walkthrough)

-- ---------------------------------------------------------------------
-- Q8. REJECT a booking and record the administrator
--     Feature: admin "Reject" button.  PHP supplies: :booking_id, :admin_id
--     "AND status = 'Pending'" stops a booking being handled twice;
--     PHP should check that 1 row was affected ($stmt->rowCount() === 1).
-- ---------------------------------------------------------------------
SET @booking_id = 5;  SET @admin_id = 2;
UPDATE bookings
   SET status = 'Rejected', handled_by = @admin_id, handled_at = NOW()
 WHERE booking_id = @booking_id AND status = 'Pending';

-- ---------------------------------------------------------------------
-- Q9. CANCEL a booking (requester cancels their own)
--     Feature: "Cancel" button on My bookings.
--     PHP supplies: :booking_id, :user_id (from session - NOT from the form)
--     Rule used (recommended default): owner only; Pending or Approved;
--     the booking must not have started yet.
--     rowCount() = 0 means "not yours / not cancellable".
-- ---------------------------------------------------------------------
SET @booking_id = 8;  SET @user_id = 4;
UPDATE bookings
   SET status = 'Cancelled'
 WHERE booking_id = @booking_id
   AND user_id    = @user_id
   AND status IN ('Pending','Approved')
   AND TIMESTAMP(booking_date, start_time) > NOW();
-- (booking #8 is already Cancelled in the sample data, so 0 rows change.)

-- ---------------------------------------------------------------------
-- Q9b. Mark finished bookings as Completed
--      Run by PHP at the start of the history/admin pages (XAMPP has no
--      scheduler). Approved bookings whose end time has passed.
-- ---------------------------------------------------------------------
UPDATE bookings
   SET status = 'Completed'
 WHERE status = 'Approved'
   AND TIMESTAMP(booking_date, end_time) < NOW();

-- ---------------------------------------------------------------------
-- Q10. Booking history (past / upcoming / cancelled)
--      Feature: history page for a user. PHP supplies: :user_id
--      (admin view: remove the user filter).
-- ---------------------------------------------------------------------
SET @user_id = 3;
SELECT bk.booking_id, r.room_name, bk.booking_date, bk.start_time, bk.end_time, bk.status,
       CASE
         WHEN bk.status = 'Cancelled' THEN 'Cancelled'
         WHEN TIMESTAMP(bk.booking_date, bk.end_time) < NOW() THEN 'Past'
         ELSE 'Upcoming'
       END AS history_group
FROM bookings bk
JOIN rooms r ON r.room_id = bk.room_id
WHERE bk.user_id = @user_id
ORDER BY bk.booking_date DESC, bk.start_time DESC;

-- ---------------------------------------------------------------------
-- Q11. Bookings per department   (report)
--      PHP supplies: nothing. Counts every request and splits by status.
-- ---------------------------------------------------------------------
SELECT u.department,
       COUNT(*)                         AS total_bookings,
       SUM(bk.status = 'Approved')      AS approved,
       SUM(bk.status = 'Completed')     AS completed,
       SUM(bk.status = 'Pending')       AS pending,
       SUM(bk.status IN ('Rejected','Cancelled')) AS rejected_or_cancelled
FROM bookings bk
JOIN users u ON u.user_id = bk.user_id
GROUP BY u.department
ORDER BY total_bookings DESC, u.department;

-- ---------------------------------------------------------------------
-- Q12. Most-used rooms   (report)
--      "Used" = Approved or Completed bookings (rec. definition).
--      Also shows total hours booked.
-- ---------------------------------------------------------------------
SELECT r.room_id, r.room_name, b.building_name,
       COUNT(*) AS times_used,
       ROUND(SUM(TIME_TO_SEC(TIMEDIFF(bk.end_time, bk.start_time))) / 3600, 1) AS hours_booked
FROM bookings bk
JOIN rooms r     ON r.room_id = bk.room_id
JOIN buildings b ON b.building_id = r.building_id
WHERE bk.status IN ('Approved','Completed')
GROUP BY r.room_id, r.room_name, b.building_name
ORDER BY times_used DESC, hours_booked DESC, r.room_name
LIMIT 5;

-- ---------------------------------------------------------------------
-- Q13. Bookings per week   (report)
--      Week starts on Monday (WEEKDAY(): Monday = 0).
-- ---------------------------------------------------------------------
SELECT DATE_SUB(bk.booking_date, INTERVAL WEEKDAY(bk.booking_date) DAY) AS week_starting,
       COUNT(*) AS total_bookings,
       SUM(bk.status IN ('Approved','Completed')) AS used_or_approved
FROM bookings bk
GROUP BY week_starting
ORDER BY week_starting;
