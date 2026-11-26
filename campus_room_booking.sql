-- =====================================================================
--  CAMPUS ROOM BOOKING SYSTEM  -  database script
--  Course: COMP3408 Database Management System (Final Project)
--  Role:   Database Designer & System Logic
--
--  WHAT THIS FILE DOES (in order)
--    1. Creates the database  campus_room_booking
--    2. Creates 7 tables (roles, users, buildings, rooms, facilities,
--       room_facilities, bookings)
--    3. Creates the rule-checking procedure + 2 triggers (safety net)
--    4. Creates the approval procedure  sp_approve_booking  (transaction)
--    5. Inserts fictional sample data
--
--  RE-RUNNING: the script drops and re-creates its own tables, so
--  importing it again RESETS the database to the sample data.
--
--  VERSION NOTES
--    * Works on MariaDB 10.4+ (what XAMPP ships) and MySQL 8.0.16+.
--      CHECK constraints are only enforced from MariaDB 10.2.1 /
--      MySQL 8.0.16. On older MySQL (5.7) CHECK is silently ignored,
--      but the triggers below still protect the most important rules.
--    * The script uses DELIMITER (needed for triggers/procedures).
--      phpMyAdmin (Import tab or SQL tab) and MySQL Workbench both
--      understand it.
--    * Storage engine: InnoDB (required for foreign keys + transactions).
-- =====================================================================

CREATE DATABASE IF NOT EXISTS campus_room_booking
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE campus_room_booking;

-- Drop in REVERSE dependency order so foreign keys do not block us.
DROP TABLE IF EXISTS bookings;
DROP TABLE IF EXISTS room_facilities;
DROP TABLE IF EXISTS facilities;
DROP TABLE IF EXISTS rooms;
DROP TABLE IF EXISTS buildings;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS roles;
DROP PROCEDURE IF EXISTS sp_validate_booking;
DROP PROCEDURE IF EXISTS sp_approve_booking;
-- (dropping a table also drops its triggers)

-- ---------------------------------------------------------------------
-- 1. roles : the kinds of user (lookup table)
-- ---------------------------------------------------------------------
CREATE TABLE roles (
  role_id    TINYINT UNSIGNED NOT NULL AUTO_INCREMENT,
  role_name  VARCHAR(20)      NOT NULL,
  PRIMARY KEY (role_id),
  UNIQUE KEY uq_roles_role_name (role_name)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 2. users : one row per person (requester or administrator)
--    campus_id = the student ID or staff ID
--    password_hash = for basic login; store ONLY a hash made by PHP
--    password_hash(), never the plain password. NULL in sample data.
-- ---------------------------------------------------------------------
CREATE TABLE users (
  user_id        INT UNSIGNED     NOT NULL AUTO_INCREMENT,
  role_id        TINYINT UNSIGNED NOT NULL,
  full_name      VARCHAR(100)     NOT NULL,
  campus_id      VARCHAR(20)      NOT NULL,
  department     VARCHAR(100)     NOT NULL,
  password_hash  VARCHAR(255)     NULL,
  created_at     DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id),
  UNIQUE KEY uq_users_campus_id (campus_id),
  KEY idx_users_department (department),
  CONSTRAINT fk_users_role
    FOREIGN KEY (role_id) REFERENCES roles (role_id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 3. buildings
-- ---------------------------------------------------------------------
CREATE TABLE buildings (
  building_id    SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
  building_name  VARCHAR(100)      NOT NULL,
  PRIMARY KEY (building_id),
  UNIQUE KEY uq_buildings_name (building_name)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 4. rooms
--    Same room_name may exist in different buildings, but not twice in
--    one building (UNIQUE on the pair).
-- ---------------------------------------------------------------------
CREATE TABLE rooms (
  room_id      INT UNSIGNED      NOT NULL AUTO_INCREMENT,
  building_id  SMALLINT UNSIGNED NOT NULL,
  room_name    VARCHAR(50)       NOT NULL,
  floor        TINYINT UNSIGNED  NOT NULL,
  room_type    ENUM('Study Room','Classroom') NOT NULL,
  capacity     SMALLINT UNSIGNED NOT NULL,
  PRIMARY KEY (room_id),
  UNIQUE KEY uq_rooms_building_name (building_id, room_name),
  KEY idx_rooms_type_capacity (room_type, capacity),
  CONSTRAINT fk_rooms_building
    FOREIGN KEY (building_id) REFERENCES buildings (building_id),
  CONSTRAINT chk_rooms_capacity CHECK (capacity > 0)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 5. facilities : types of equipment
-- ---------------------------------------------------------------------
CREATE TABLE facilities (
  facility_id    SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
  facility_name  VARCHAR(50)       NOT NULL,
  PRIMARY KEY (facility_id),
  UNIQUE KEY uq_facilities_name (facility_name)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 6. room_facilities : link table (many-to-many rooms <-> facilities)
--    The PAIR (room_id, facility_id) is the primary key, so a room
--    cannot list the same facility twice.
-- ---------------------------------------------------------------------
CREATE TABLE room_facilities (
  room_id      INT UNSIGNED      NOT NULL,
  facility_id  SMALLINT UNSIGNED NOT NULL,
  PRIMARY KEY (room_id, facility_id),
  KEY idx_room_facilities_facility (facility_id),
  CONSTRAINT fk_rf_room
    FOREIGN KEY (room_id)     REFERENCES rooms (room_id)
    ON DELETE CASCADE,
  CONSTRAINT fk_rf_facility
    FOREIGN KEY (facility_id) REFERENCES facilities (facility_id)
    ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 7. bookings : one row per request
--    user_id    = the requester
--    handled_by = the administrator who approved/rejected (NULL until then)
--    No ON DELETE CASCADE here on purpose: you cannot delete a user or
--    room that has bookings, so booking history is never lost.
-- ---------------------------------------------------------------------
CREATE TABLE bookings (
  booking_id      INT UNSIGNED      NOT NULL AUTO_INCREMENT,
  user_id         INT UNSIGNED      NOT NULL,
  room_id         INT UNSIGNED      NOT NULL,
  booking_date    DATE              NOT NULL,
  start_time      TIME              NOT NULL,
  end_time        TIME              NOT NULL,
  purpose         VARCHAR(255)      NOT NULL,
  attendee_count  SMALLINT UNSIGNED NOT NULL,
  status          ENUM('Pending','Approved','Rejected','Cancelled','Completed')
                  NOT NULL DEFAULT 'Pending',
  created_at      DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
  handled_by      INT UNSIGNED      NULL,
  handled_at      DATETIME          NULL,
  PRIMARY KEY (booking_id),
  -- speeds up the availability / conflict search (room + day + status)
  KEY idx_bookings_room_date_status (room_id, booking_date, status),
  KEY idx_bookings_user_date (user_id, booking_date),
  KEY idx_bookings_status (status),
  KEY idx_bookings_handled_by (handled_by),
  CONSTRAINT fk_bookings_user
    FOREIGN KEY (user_id)    REFERENCES users (user_id),
  CONSTRAINT fk_bookings_room
    FOREIGN KEY (room_id)    REFERENCES rooms (room_id),
  CONSTRAINT fk_bookings_handler
    FOREIGN KEY (handled_by) REFERENCES users (user_id),
  CONSTRAINT chk_bookings_time_order CHECK (end_time > start_time),
  CONSTRAINT chk_bookings_attendees  CHECK (attendee_count > 0),
  -- handled_by and handled_at are either both filled or both empty
  CONSTRAINT chk_bookings_handled_pair CHECK (
       (handled_by IS NULL     AND handled_at IS NULL)
    OR (handled_by IS NOT NULL AND handled_at IS NOT NULL))
) ENGINE=InnoDB;

-- =====================================================================
--  RULES THAT A SIMPLE CHECK CANNOT EXPRESS
--  (they compare a booking with OTHER rows / OTHER tables)
-- =====================================================================
DELIMITER $$

-- ---------------------------------------------------------------------
-- sp_validate_booking : the shared rule-checker. Raises an error
-- (SQLSTATE 45000) with a readable message when a rule is broken.
--   p_booking_id : NULL for a brand-new row, else the row's own id
--                  (so a booking is never compared with itself)
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_validate_booking(
  IN p_booking_id  INT UNSIGNED,
  IN p_room_id     INT UNSIGNED,
  IN p_date        DATE,
  IN p_start       TIME,
  IN p_end         TIME,
  IN p_attendees   SMALLINT UNSIGNED,
  IN p_status      VARCHAR(20),
  IN p_handled_by  INT UNSIGNED
)
BEGIN
  DECLARE v_capacity  INT DEFAULT NULL;
  DECLARE v_is_admin  INT DEFAULT 0;
  DECLARE v_conflicts INT DEFAULT 0;

  -- Rule: attendees must not exceed the room capacity
  SELECT capacity INTO v_capacity FROM rooms WHERE room_id = p_room_id;
  IF v_capacity IS NOT NULL AND p_attendees > v_capacity THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Attendee count exceeds the room capacity';
  END IF;

  -- Rule: the handler must be a user with the Administrator role
  IF p_handled_by IS NOT NULL THEN
    SELECT COUNT(*) INTO v_is_admin
    FROM users u JOIN roles r ON r.role_id = u.role_id
    WHERE u.user_id = p_handled_by AND r.role_name = 'Administrator';
    IF v_is_admin = 0 THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'handled_by must be a user with the Administrator role';
    END IF;
  END IF;

  -- Rule: Approved / Rejected need an administrator on record
  IF p_status IN ('Approved','Rejected') AND p_handled_by IS NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Approved or Rejected bookings need handled_by';
  END IF;

  -- Rule: no two APPROVED bookings may overlap in the same room + date.
  -- Overlap test:  existing_start < requested_end AND existing_end > requested_start
  -- (back-to-back, e.g. 09:00-10:00 then 10:00-11:00, is NOT an overlap)
  IF p_status = 'Approved' THEN
    SELECT COUNT(*) INTO v_conflicts
    FROM bookings b
    WHERE b.room_id      = p_room_id
      AND b.booking_date = p_date
      AND b.status       = 'Approved'
      AND b.start_time   < p_end
      AND b.end_time     > p_start
      AND (p_booking_id IS NULL OR b.booking_id <> p_booking_id);
    IF v_conflicts > 0 THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Conflict: room already has an Approved booking in this time slot';
    END IF;
  END IF;
END$$

-- ---------------------------------------------------------------------
-- Trigger: runs automatically BEFORE every new booking row is saved
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_bookings_before_insert
BEFORE INSERT ON bookings
FOR EACH ROW
BEGIN
  CALL sp_validate_booking(NULL, NEW.room_id, NEW.booking_date,
       NEW.start_time, NEW.end_time, NEW.attendee_count,
       NEW.status, NEW.handled_by);
END$$

-- ---------------------------------------------------------------------
-- Trigger: runs automatically BEFORE every booking row is changed.
-- Also guards the allowed status changes:
--   Pending  -> Approved | Rejected | Cancelled
--   Approved -> Cancelled | Completed
--   Rejected / Cancelled / Completed are final.
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_bookings_before_update
BEFORE UPDATE ON bookings
FOR EACH ROW
BEGIN
  IF NEW.status <> OLD.status THEN
    IF NOT ( (OLD.status = 'Pending'  AND NEW.status IN ('Approved','Rejected','Cancelled'))
          OR (OLD.status = 'Approved' AND NEW.status IN ('Cancelled','Completed')) ) THEN
      SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid status change for this booking';
    END IF;
  END IF;

  CALL sp_validate_booking(OLD.booking_id, NEW.room_id, NEW.booking_date,
       NEW.start_time, NEW.end_time, NEW.attendee_count,
       NEW.status, NEW.handled_by);
END$$

-- ---------------------------------------------------------------------
-- sp_approve_booking : the SAFE way to approve (use this from PHP).
--
-- Why a transaction + lock?  Two admins could click "Approve" on two
-- overlapping requests at the same moment. Both checks could pass before
-- either saves (a race condition). So we:
--   1. START TRANSACTION (all steps succeed together, or none do)
--   2. lock the booking row, then lock the ROOM row (FOR UPDATE). Anyone
--      else approving a booking for the same room must WAIT here.
--   3. update the status; the trigger runs the conflict check against
--      the latest committed data
--   4. COMMIT (save + release locks)   or   ROLLBACK on any error
-- READ COMMITTED makes sure the conflict check sees bookings committed
-- by whoever held the lock before us.
-- ---------------------------------------------------------------------
CREATE PROCEDURE sp_approve_booking(
  IN p_booking_id INT UNSIGNED,
  IN p_admin_id   INT UNSIGNED
)
BEGIN
  DECLARE v_room_id   INT UNSIGNED DEFAULT NULL;
  DECLARE v_status    VARCHAR(20)  DEFAULT NULL;
  DECLARE v_end_dt    DATETIME     DEFAULT NULL;
  DECLARE v_room_lock INT UNSIGNED DEFAULT NULL;

  -- On ANY error: undo everything, then pass the error up to PHP.
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;

  -- Lock this booking and read its current state
  SELECT room_id, status, TIMESTAMP(booking_date, end_time)
    INTO v_room_id, v_status, v_end_dt
  FROM bookings
  WHERE booking_id = p_booking_id
  FOR UPDATE;

  IF v_room_id IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Booking not found';
  END IF;

  -- Lock the room: the "turnstile" that serialises approvals per room
  SELECT room_id INTO v_room_lock FROM rooms WHERE room_id = v_room_id FOR UPDATE;

  IF v_status <> 'Pending' THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Only Pending bookings can be approved';
  END IF;

  IF v_end_dt < NOW() THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Cannot approve a booking whose time has already passed';
  END IF;

  -- The trigger checks capacity, admin role and overlap with Approved rows
  UPDATE bookings
     SET status = 'Approved', handled_by = p_admin_id, handled_at = NOW()
   WHERE booking_id = p_booking_id;

  COMMIT;
END$$

DELIMITER ;

-- =====================================================================
--  SAMPLE DATA  (fictional - no real people, no passwords)
--  Booking dates are RELATIVE to today (CURDATE()) so the demo always
--  has upcoming and past bookings, whenever you import the file.
-- =====================================================================

INSERT INTO roles (role_name) VALUES ('Requester'), ('Administrator');
-- role_id 1 = Requester, 2 = Administrator

INSERT INTO users (role_id, full_name, campus_id, department) VALUES
  (2, 'Dewi Lestari (demo)',    'A-0001',   'Facilities'),         -- user_id 1 (admin)
  (2, 'Rahmat Hidayat (demo)',  'A-0002',   'Academic Affairs'),   -- user_id 2 (admin)
  (1, 'Aldo Pratama (demo)',    'S2026001', 'Computer Science'),   -- user_id 3
  (1, 'Bella Santoso (demo)',   'S2026002', 'Computer Science'),   -- user_id 4
  (1, 'Citra Wijaya (demo)',    'S2026003', 'Business'),           -- user_id 5
  (1, 'Dimas Kurniawan (demo)', 'S2026004', 'Engineering'),        -- user_id 6
  (1, 'Eka Putri (demo)',       'T-0101',   'Business'),           -- user_id 7 (staff)
  (1, 'Farhan Malik (demo)',    'S2026005', 'Engineering');        -- user_id 8

INSERT INTO buildings (building_name) VALUES
  ('Library Building'),       -- 1
  ('Engineering Building'),   -- 2
  ('Business Building');      -- 3

INSERT INTO rooms (building_id, room_name, floor, room_type, capacity) VALUES
  (1, 'Study Room L1',  1, 'Study Room',  6),   -- room_id 1
  (1, 'Study Room L2',  1, 'Study Room',  6),   -- 2
  (1, 'Study Room L3',  2, 'Study Room', 10),   -- 3
  (2, 'Classroom E101', 1, 'Classroom',  40),   -- 4
  (2, 'Classroom E201', 2, 'Classroom',  30),   -- 5
  (2, 'Study Room ES1', 2, 'Study Room',  8),   -- 6
  (3, 'Classroom B301', 3, 'Classroom',  50),   -- 7
  (3, 'Study Room BS1', 1, 'Study Room',  6);   -- 8

INSERT INTO facilities (facility_name) VALUES
  ('Projector'),        -- 1
  ('Whiteboard'),       -- 2
  ('TV Screen'),        -- 3
  ('Air Conditioning'); -- 4

INSERT INTO room_facilities (room_id, facility_id) VALUES
  (1,2),(1,4),
  (2,2),(2,4),
  (3,2),(3,3),(3,4),
  (4,1),(4,2),(4,4),
  (5,1),(5,2),(5,4),
  (6,2),(6,3),
  (7,1),(7,2),(7,3),(7,4),
  (8,2);

-- Bookings. Columns: user, room, date, start, end, purpose, attendees,
--                    status, handled_by, handled_at
-- Inserted in an order where every Approved row is conflict-free.
INSERT INTO bookings
  (user_id, room_id, booking_date, start_time, end_time, purpose,
   attendee_count, status, handled_by, handled_at)
VALUES
  -- Room 1 tomorrow: one Approved + two Pending that compete with it
  (3, 1, CURDATE() + INTERVAL 1 DAY, '09:00','11:00', 'DBMS group project study', 4, 'Approved', 1, NOW()),          -- #1
  (4, 1, CURDATE() + INTERVAL 1 DAY, '10:00','12:00', 'Exam revision group',      3, 'Pending',  NULL, NULL),         -- #2 overlaps #1
  (5, 1, CURDATE() + INTERVAL 1 DAY, '11:00','13:00', 'Business case discussion', 5, 'Pending',  NULL, NULL),         -- #3 back-to-back with #1 (allowed)
  -- Room 4 (capacity 40), day after tomorrow
  (7, 4, CURDATE() + INTERVAL 2 DAY, '13:00','15:00', 'Guest lecture',           35, 'Approved', 2, NOW()),          -- #4
  (6, 4, CURDATE() + INTERVAL 2 DAY, '14:00','16:00', 'Robotics club meeting',   30, 'Pending',  NULL, NULL),         -- #5 overlaps #4
  (8, 5, CURDATE() + INTERVAL 3 DAY, '09:00','12:00', 'Circuits workshop',       25, 'Pending',  NULL, NULL),         -- #6
  -- Rejected / Cancelled examples
  (3, 7, CURDATE() + INTERVAL 4 DAY, '08:00','10:00', 'Programming club meeting',40, 'Rejected', 2, NOW()),          -- #7
  (4, 2, CURDATE() + INTERVAL 1 DAY, '15:00','16:00', 'Quick study session',      4, 'Cancelled',NULL, NULL),         -- #8
  -- Past (Completed) bookings, spread over different weeks
  (5, 3, CURDATE() - INTERVAL 3 DAY, '10:00','12:00', 'Thesis discussion',        8, 'Completed', 1, NOW() - INTERVAL 5 DAY), -- #9
  (6, 6, CURDATE() - INTERVAL 5 DAY, '13:00','15:00', 'Lab review',               6, 'Completed', 2, NOW() - INTERVAL 7 DAY), -- #10
  (3, 1, CURDATE() - INTERVAL 8 DAY, '09:00','11:00', 'DBMS lab preparation',     5, 'Completed', 1, NOW() - INTERVAL 10 DAY),-- #11
  (7, 4, CURDATE() - INTERVAL 9 DAY, '08:00','10:00', 'Staff workshop',          30, 'Completed', 2, NOW() - INTERVAL 11 DAY),-- #12
  (8, 1, CURDATE() - INTERVAL 10 DAY,'13:00','14:30', 'Study group',              4, 'Completed', 1, NOW() - INTERVAL 12 DAY);-- #13

-- Quick check after import. Expected: roles 2, users 8, rooms 8,
-- facilities 4, room_facilities 20, bookings 13
-- SELECT (SELECT COUNT(*) FROM roles) roles, (SELECT COUNT(*) FROM users) users,
--        (SELECT COUNT(*) FROM rooms) rooms, (SELECT COUNT(*) FROM facilities) facilities,
--        (SELECT COUNT(*) FROM room_facilities) room_facilities,
--        (SELECT COUNT(*) FROM bookings) bookings;
