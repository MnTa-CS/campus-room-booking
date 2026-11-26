-- =====================================================================
--  CAMPUS ROOM BOOKING SYSTEM  -  conflict & rule tests
--  Start from a FRESH import of campus_room_booking.sql, then run the
--  tests ONE BLOCK AT A TIME (phpMyAdmin stops a multi-statement run at
--  the first error, and several tests are SUPPOSED to give an error).
--
--  Sample data reminder (dates are tomorrow = T+1, etc.):
--    #1 Room 1  T+1  09:00-11:00  Approved
--    #2 Room 1  T+1  10:00-12:00  Pending   (overlaps #1)
--    #3 Room 1  T+1  11:00-13:00  Pending   (touches #1 at 11:00 only)
--    #4 Room 4  T+2  13:00-15:00  Approved
--    #5 Room 4  T+2  14:00-16:00  Pending   (overlaps #4)
--    #6 Room 5  T+3  09:00-12:00  Pending   (no competitor)
--    #7 Room 7  T+4  08:00-10:00  Rejected
-- =====================================================================
USE campus_room_booking;

-- ---------------------------------------------------------------------
-- TEST 1  Overlapping approval is REFUSED
-- Expected: ERROR 1644 (45000) "Conflict: room already has an Approved
--           booking in this time slot"; booking #2 stays Pending.
-- ---------------------------------------------------------------------
CALL sp_approve_booking(2, 1);
SELECT booking_id, status, handled_by FROM bookings WHERE booking_id = 2;   -- still Pending

-- ---------------------------------------------------------------------
-- TEST 2  Back-to-back (non-overlapping) approval is ACCEPTED
-- #3 starts at 11:00, exactly when #1 ends: 09:00 < 13:00 yes, but
-- #1.end(11:00) > #3.start(11:00) is FALSE, so no overlap.
-- Expected: success; #3 becomes Approved with handled_by = 1.
-- ---------------------------------------------------------------------
CALL sp_approve_booking(3, 1);
SELECT booking_id, status, handled_by, handled_at FROM bookings WHERE booking_id = 3;

-- ---------------------------------------------------------------------
-- TEST 3  A different room is never affected
-- Expected: success; #6 (Room 5) becomes Approved.
-- ---------------------------------------------------------------------
CALL sp_approve_booking(6, 2);
SELECT booking_id, status, handled_by FROM bookings WHERE booking_id = 6;

-- ---------------------------------------------------------------------
-- TEST 4  The database refuses a conflict even if someone skips the
--         procedure and writes a plain UPDATE (trigger safety net)
-- Expected: ERROR 1644 "Conflict: room already has an Approved booking..."
-- ---------------------------------------------------------------------
UPDATE bookings SET status = 'Approved', handled_by = 1, handled_at = NOW()
WHERE booking_id = 5;

-- ---------------------------------------------------------------------
-- TEST 5  Inserting an Approved row that overlaps is refused
-- Expected: ERROR 1644 (room 1, 10:30-11:30 overlaps #1 and #3)
-- ---------------------------------------------------------------------
INSERT INTO bookings (user_id, room_id, booking_date, start_time, end_time,
                      purpose, attendee_count, status, handled_by, handled_at)
VALUES (4, 1, CURDATE() + INTERVAL 1 DAY, '10:30', '11:30', 'Sneaky', 3,
        'Approved', 1, NOW());

-- ---------------------------------------------------------------------
-- TEST 6  Several PENDING requests for one slot ARE allowed
-- Expected: success (Pending never blocks).
-- ---------------------------------------------------------------------
INSERT INTO bookings (user_id, room_id, booking_date, start_time, end_time, purpose, attendee_count)
VALUES (4, 1, CURDATE() + INTERVAL 1 DAY, '09:30', '10:30', 'Another request, same slot', 3);

-- ---------------------------------------------------------------------
-- TEST 7  Too many attendees (Room 1 capacity is 6)
-- Expected: ERROR 1644 "Attendee count exceeds the room capacity"
-- ---------------------------------------------------------------------
INSERT INTO bookings (user_id, room_id, booking_date, start_time, end_time, purpose, attendee_count)
VALUES (4, 1, CURDATE() + INTERVAL 6 DAY, '09:00', '10:00', 'Too many people', 7);

-- ---------------------------------------------------------------------
-- TEST 8  End time not after start time
-- Expected: ERROR 4025 / 3819 "CONSTRAINT chk_bookings_time_order failed"
-- ---------------------------------------------------------------------
INSERT INTO bookings (user_id, room_id, booking_date, start_time, end_time, purpose, attendee_count)
VALUES (4, 2, CURDATE() + INTERVAL 6 DAY, '10:00', '10:00', 'Zero length', 2);

-- ---------------------------------------------------------------------
-- TEST 9  Attendee count must be positive
-- Expected: ERROR "CONSTRAINT chk_bookings_attendees failed"
-- ---------------------------------------------------------------------
INSERT INTO bookings (user_id, room_id, booking_date, start_time, end_time, purpose, attendee_count)
VALUES (4, 2, CURDATE() + INTERVAL 6 DAY, '10:00', '11:00', 'Nobody', 0);

-- ---------------------------------------------------------------------
-- TEST 10  Unknown room / user (foreign key)
-- Expected: ERROR 1452 "Cannot add or update a child row: a foreign key
--           constraint fails"
-- ---------------------------------------------------------------------
INSERT INTO bookings (user_id, room_id, booking_date, start_time, end_time, purpose, attendee_count)
VALUES (4, 999, CURDATE() + INTERVAL 6 DAY, '10:00', '11:00', 'No such room', 2);

-- ---------------------------------------------------------------------
-- TEST 11  Handler must be an Administrator (user 3 is a Requester)
-- Expected: ERROR 1644 "handled_by must be a user with the Administrator role"
-- ---------------------------------------------------------------------
UPDATE bookings SET status = 'Rejected', handled_by = 3, handled_at = NOW()
WHERE booking_id = 5;

-- ---------------------------------------------------------------------
-- TEST 12  Handling the same booking twice / invalid status change
-- (a) approving an already Approved booking -> "Only Pending bookings can be approved"
-- (b) changing a Rejected booking back to Approved -> "Invalid status change..."
-- ---------------------------------------------------------------------
CALL sp_approve_booking(1, 1);
UPDATE bookings SET status = 'Approved', handled_by = 1, handled_at = NOW()
WHERE booking_id = 7;

-- ---------------------------------------------------------------------
-- TEST 13  Only the owner may cancel (booking #5 belongs to user 6)
-- Expected: 0 rows changed when user 4 tries; 1 row when user 6 tries.
-- ---------------------------------------------------------------------
UPDATE bookings SET status = 'Cancelled'
WHERE booking_id = 5 AND user_id = 4 AND status IN ('Pending','Approved')
  AND TIMESTAMP(booking_date, start_time) > NOW();       -- 0 rows
UPDATE bookings SET status = 'Cancelled'
WHERE booking_id = 5 AND user_id = 6 AND status IN ('Pending','Approved')
  AND TIMESTAMP(booking_date, start_time) > NOW();       -- 1 row

-- ---------------------------------------------------------------------
-- FINAL CHECK: no two Approved bookings may overlap. This query must
-- return ZERO rows at any time.
-- ---------------------------------------------------------------------
SELECT a.booking_id AS booking_a, b.booking_id AS booking_b, a.room_id, a.booking_date
FROM bookings a
JOIN bookings b
  ON a.room_id = b.room_id AND a.booking_date = b.booking_date
 AND a.booking_id < b.booking_id
 AND a.start_time < b.end_time AND a.end_time > b.start_time
WHERE a.status = 'Approved' AND b.status = 'Approved';
