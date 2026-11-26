# Campus Room Booking System — Database

COMP3408 Database Management System, Final Project (Database Designer & System Logic part).

Stack: MySQL/MariaDB (XAMPP), PHP (PDO), HTML/CSS/Bootstrap.

## Files
| File | Purpose |
|---|---|
| `campus_room_booking.sql` | Import this: creates database `campus_room_booking`, 7 tables, rules, approval procedure and sample data |
| `queries.sql` | The 13 important queries (Q1–Q13) |
| `test_conflict.sql` | 13 tests for the booking rules (run one block at a time) |
| `erd.png`, `erd.mmd` | Entity Relationship Diagram (picture + Mermaid source) |
| `DATABASE_DESIGN_GUIDE.md` | Design explanation, normalization, transactions, validation checklist, backend handover |
| `test-evidence/` | Screenshots and logs of test runs |

## Setup
1. Start Apache and MySQL in XAMPP.
2. phpMyAdmin (`http://localhost/phpmyadmin`) → Import → `campus_room_booking.sql` → Go.
3. Expected row counts: roles 2, users 8, rooms 8, facilities 4, room_facilities 20, bookings 13.

Re-importing resets the database to the sample data.

## For the backend developer
- Approve bookings **only** with `CALL sp_approve_booking(:booking_id, :admin_id)`.
- Booking statuses: `Pending`, `Approved`, `Rejected`, `Cancelled`, `Completed`.
- Full column list and rules: see section 10 of `DATABASE_DESIGN_GUIDE.md`.
- Keep database credentials in `config.local.php` (ignored by git).
