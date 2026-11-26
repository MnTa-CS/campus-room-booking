# Database Testing

This section records how the Campus Room Booking database was tested and what the results were. All tests below were run by the database designer on the group's development machine using the provided SQL files.

## 1. Test environment

| Item | Value |
|---|---|
| Operating system | Windows |
| Server package | XAMPP (Apache + MySQL) |
| Database server | MariaDB 10.11.19 (`SELECT VERSION();`) |
| Tool | phpMyAdmin (SQL tab and Import tab) |
| Database | `campus_room_booking` |
| Import file | `campus_room_booking.sql` (imported 25 Nov 2026) |
| Test date | 26 Nov 2026 |

*Figure 1: Database version.* (`test-evidence/12_version.png`)

## 2. Method

1. Import `campus_room_booking.sql` and check that the database objects exist.
2. Run each rule test from `test_conflict.sql` as a separate SQL statement.
3. For rule-violation tests, the **expected result is an error**: the test passes when the database refuses the invalid action.
4. After the tests, run a query that searches for any two overlapping Approved bookings. It must return no rows.
5. Run the available-rooms query (Q3) with and without a clash.

A screenshot was taken for each result.

## 3. Results

### 3.1 Import and structure

| Check | Expected | Actual | Result | Figure |
|---|---|---|---|---|
| Import of `campus_room_booking.sql` | Import finishes; all 30 statements executed | "Import has been successfully finished, 30 queries executed" | Pass | `01_import_success.png` |
| Stored procedures (`SHOW PROCEDURE STATUS`) | 2 procedures | `sp_approve_booking`, `sp_validate_booking` | Pass | `02_procedures.png` |
| Triggers (`SHOW TRIGGERS`) | 2 triggers | `trg_bookings_before_insert`, `trg_bookings_before_update` | Pass | `03_triggers.png` |
| Row counts | roles 2, users 8, rooms 8, facilities 4, room_facilities 20, bookings 13 | 2, 8, 8, 4, 20, 13 | Pass | `04_counts.png` |

Note: phpMyAdmin printed several `#1046 No database selected` lines in the import log. The database objects and data are all present (rows above), so these were display messages and not failed statements.

### 3.2 Booking rule tests

| Test | Rule tested | Action | Expected | Actual | Result | Figure |
|---|---|---|---|---|---|---|
| 1 | No overlapping Approved bookings | `CALL sp_approve_booking(2, 1)` — booking #2 (10:00–12:00) overlaps Approved #1 (09:00–11:00) in the same room and date | Refused | `#1644 - Conflict: room already has an Approved booking in this time slot` | Pass | `05_test1_conflict.png` |
| 2 | Back-to-back bookings are allowed | `CALL sp_approve_booking(3, 1)` — booking #3 (11:00–13:00) starts exactly when #1 ends | Accepted | Success; booking #3 is `Approved`, `handled_by` = 1, `handled_at` = 2026-11-26 09:46:43 | Pass | `06_test2_approved.png` |
| 4 | Conflict rule cannot be bypassed | Plain `UPDATE` setting overlapping booking #5 to Approved (no procedure) | Refused | `#1644 - Conflict: room already has an Approved booking in this time slot` | Pass | `07_test4_trigger.png` |
| 7 | Attendees must not exceed room capacity | Insert 7 attendees into a 6-seat room | Refused | `#1644 - Attendee count exceeds the room capacity` | Pass | `08_test7_capacity.png` |
| 8 | End time must be later than start time | Insert booking with start 10:00 and end 10:00 | Refused | `#4025 - CONSTRAINT chk_bookings_time_order failed` | Pass | `09_test8_check.png` |
| 11 | Only an administrator can handle a booking | Set `handled_by` to user 3 (a Requester) | Refused | `#1644 - handled_by must be a user with the Administrator role` | Pass | `10_test11_admin.png` |
| Final | No two Approved bookings overlap anywhere | Self-join query on Approved bookings | 0 rows | 0 rows | Pass | `11_overlap_check_zero.png` |

### 3.3 Query test: available rooms (Q3)

| Case | Input | Expected | Actual | Result | Figure |
|---|---|---|---|---|---|
| Day with no bookings | Tomorrow, 10:00–11:00, 4 attendees | All 8 rooms available | 8 rooms | Pass | `13_q3_all_rooms.png` |
| Day with an Approved booking | Today, 10:00–11:00, 4 attendees | 7 rooms; Study Room L1 excluded (Approved 09:00–11:00) | 7 rooms; Study Room L1 not listed | Pass | `14_q3_l1_excluded.png` |

## 4. How the rules are enforced

- **Overlap:** two bookings conflict when `existing_start < requested_end AND existing_end > requested_start`, in the same room on the same date, considering only Approved bookings. A `CHECK` constraint cannot compare different rows, so the rule is checked by the procedure `sp_validate_booking`, which the triggers call on every insert and update. Test 1 and Test 4 show that the rule holds both through the approval procedure and through plain SQL.
- **Back-to-back bookings:** because the test uses strict `<` and `>`, a booking that starts exactly when another ends does not conflict (Test 2).
- **Constraints:** the time-order rule is a `CHECK` constraint on the table (Test 8). Capacity and administrator-role rules compare against other tables, so they are enforced in the validation procedure (Tests 7 and 11).
- **Transaction:** `sp_approve_booking` runs as one transaction. It locks the booking and its room, checks the booking is Pending, then updates it. If any rule fails, `ROLLBACK` undoes everything and the error is returned to the application, as in Test 1, where booking #2 stayed Pending.

## 5. Concurrent approval (supplementary experiment)

Two administrators approving overlapping requests for the same room at the same moment was tested separately on a test server (MariaDB 10.11.14) by simulating a delay between the conflict check and the save, using two simultaneous sessions:

- Without locking the room, both bookings became Approved (a double booking).
- With the room lock used in `sp_approve_booking`, the second approval was refused with the conflict message.

This experiment was run by the database designer in a separate environment, not on the XAMPP machine in section 1.

## 6. Conclusion and limitations

The database accepts valid bookings and refuses every invalid case tested: overlapping approvals, over-capacity requests, invalid times, and non-administrator handlers. No overlapping Approved bookings were found after testing.

Limits of this testing:
- Only the database was tested. The PHP application and its pages were not part of these tests.
- Of the 13 queries in `queries.sql`, Q3 was run and recorded here. The others were checked in the design stage but not screenshotted.
- Tests 3, 5, 6, 9, 10, 12 and 13 in `test_conflict.sql` were not recorded on the XAMPP machine.
- Sample booking dates are relative to the import date, so the data should be re-imported before a demonstration.
