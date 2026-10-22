-- ============================================================================
-- SMART HOSTEL MAINTENANCE REQUEST AND COMPLAINT MANAGEMENT SYSTEM
-- Oracle Database / SQL*Plus implementation
--
-- Course   : Database Systems (BCSE302L)     Slot : D2+TD2
-- Faculty  : Mr. Nageshwar Rao
-- Students : Rania Sondhi (24BCE2798), Shreya Kothiyal (24BCE2793)
--
-- Run in your own university schema:   SQL> @Hostel_Maintenance_Oracle_SQLPlus.sql
-- The script only touches the tables, views, sequences, triggers and procedures
-- created below. To start over, use the cleanup block just under this header.
-- ============================================================================

SET DEFINE OFF
SET PAGESIZE 100
SET LINESIZE 200
SET FEEDBACK ON
SET VERIFY OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

-- ----------------------------------------------------------------------------
-- OPTIONAL CLEANUP (only when re-running in the same schema)
-- Remove the leading "-- " on the lines below, run them once, then put it back.
-- ----------------------------------------------------------------------------
-- DROP VIEW V_COMPLAINT_DASHBOARD;
-- DROP VIEW V_STAFF_WORKLOAD;
-- DROP VIEW V_HOSTEL_SUMMARY;
-- DROP TABLE Complaint_History CASCADE CONSTRAINTS PURGE;
-- DROP TABLE Feedback CASCADE CONSTRAINTS PURGE;
-- DROP TABLE Complaints CASCADE CONSTRAINTS PURGE;
-- DROP TABLE Complaint_Status CASCADE CONSTRAINTS PURGE;
-- DROP TABLE Categories CASCADE CONSTRAINTS PURGE;
-- DROP TABLE Staff CASCADE CONSTRAINTS PURGE;
-- DROP TABLE Students CASCADE CONSTRAINTS PURGE;
-- DROP TABLE Rooms CASCADE CONSTRAINTS PURGE;
-- DROP TABLE Hostels CASCADE CONSTRAINTS PURGE;
-- DROP SEQUENCE seq_complaint;
-- DROP SEQUENCE seq_feedback;
-- DROP SEQUENCE seq_history;
-- DROP PROCEDURE assign_complaint;
-- DROP PROCEDURE update_complaint_status;
-- DROP PROCEDURE hostel_report;
-- DROP FUNCTION staff_active_load;
-- DROP FUNCTION avg_resolution_days;

PROMPT ============================================================
PROMPT SMART HOSTEL MAINTENANCE REQUEST AND COMPLAINT MANAGEMENT
PROMPT ============================================================

-- ============================================================================
-- 1. MASTER TABLES
-- ============================================================================
CREATE TABLE Hostels (
    hostel_id       NUMBER(4) CONSTRAINT pk_hostels PRIMARY KEY,
    hostel_name     VARCHAR2(60) NOT NULL,
    hostel_type     VARCHAR2(10) NOT NULL
                    CONSTRAINT ck_hostel_type CHECK (hostel_type IN ('BOYS','GIRLS','MIXED')),
    warden_name     VARCHAR2(80) NOT NULL,
    contact_no      VARCHAR2(15)
);

CREATE TABLE Rooms (
    room_id         NUMBER(5) CONSTRAINT pk_rooms PRIMARY KEY,
    hostel_id       NUMBER(4) NOT NULL,
    room_number     VARCHAR2(10) NOT NULL,
    floor_no        NUMBER(2) DEFAULT 0 NOT NULL,
    room_capacity   NUMBER(2) DEFAULT 2 NOT NULL,
    CONSTRAINT fk_rooms_hostel FOREIGN KEY (hostel_id) REFERENCES Hostels(hostel_id),
    CONSTRAINT uq_hostel_room UNIQUE (hostel_id, room_number),
    CONSTRAINT ck_room_capacity CHECK (room_capacity BETWEEN 1 AND 8)
);

CREATE TABLE Students (
    student_id      NUMBER(8) CONSTRAINT pk_students PRIMARY KEY,
    student_name    VARCHAR2(80) NOT NULL,
    email           VARCHAR2(100) NOT NULL CONSTRAINT uq_students_email UNIQUE,
    phone_no        VARCHAR2(15),
    room_id         NUMBER(5) NOT NULL,
    CONSTRAINT fk_students_room FOREIGN KEY (room_id) REFERENCES Rooms(room_id)
);

CREATE TABLE Staff (
    staff_id        NUMBER(5) CONSTRAINT pk_staff PRIMARY KEY,
    staff_name      VARCHAR2(80) NOT NULL,
    role_name       VARCHAR2(40) NOT NULL,
    phone_no        VARCHAR2(15),
    availability    VARCHAR2(12) DEFAULT 'AVAILABLE' NOT NULL
                    CONSTRAINT ck_staff_availability CHECK
                    (availability IN ('AVAILABLE','BUSY','OFF_DUTY'))
);

-- handler_role links a category to the staff role that normally fixes it.
-- The assign_complaint procedure uses it to pick a person.
CREATE TABLE Categories (
    category_id     NUMBER(3) CONSTRAINT pk_categories PRIMARY KEY,
    category_name   VARCHAR2(40) NOT NULL CONSTRAINT uq_category_name UNIQUE,
    description     VARCHAR2(200),
    handler_role    VARCHAR2(40) NOT NULL
);

CREATE TABLE Complaint_Status (
    status_id       NUMBER(2) CONSTRAINT pk_status PRIMARY KEY,
    status_name     VARCHAR2(20) NOT NULL CONSTRAINT uq_status_name UNIQUE
                    CONSTRAINT ck_status_name CHECK
                    (status_name IN ('SUBMITTED','ASSIGNED','IN_PROGRESS','RESOLVED','CLOSED'))
);

-- ============================================================================
-- 2. TRANSACTION TABLES
-- ============================================================================
-- room_id on Complaints is where the fault is. It is usually the student's own
-- room, so reports by room do not need a join through Students.
CREATE TABLE Complaints (
    complaint_id    NUMBER(8) CONSTRAINT pk_complaints PRIMARY KEY,
    student_id      NUMBER(8) NOT NULL,
    category_id     NUMBER(3) NOT NULL,
    status_id       NUMBER(2) DEFAULT 1 NOT NULL,
    staff_id        NUMBER(5),
    room_id         NUMBER(5) NOT NULL,
    complaint_title VARCHAR2(100) NOT NULL,
    complaint_desc  VARCHAR2(500) NOT NULL,
    priority_level  VARCHAR2(10) DEFAULT 'MEDIUM' NOT NULL
                    CONSTRAINT ck_complaint_priority CHECK
                    (priority_level IN ('LOW','MEDIUM','HIGH','URGENT')),
    created_at      DATE DEFAULT SYSDATE NOT NULL,
    resolved_at     DATE,
    CONSTRAINT fk_complaint_student FOREIGN KEY (student_id) REFERENCES Students(student_id),
    CONSTRAINT fk_complaint_category FOREIGN KEY (category_id) REFERENCES Categories(category_id),
    CONSTRAINT fk_complaint_status FOREIGN KEY (status_id) REFERENCES Complaint_Status(status_id),
    CONSTRAINT fk_complaint_staff FOREIGN KEY (staff_id) REFERENCES Staff(staff_id),
    CONSTRAINT fk_complaint_room FOREIGN KEY (room_id) REFERENCES Rooms(room_id),
    CONSTRAINT ck_resolution_date CHECK (resolved_at IS NULL OR resolved_at >= created_at)
);

CREATE TABLE Feedback (
    feedback_id     NUMBER(8) CONSTRAINT pk_feedback PRIMARY KEY,
    complaint_id    NUMBER(8) NOT NULL,
    rating          NUMBER(1) NOT NULL CONSTRAINT ck_feedback_rating CHECK (rating BETWEEN 1 AND 5),
    comments        VARCHAR2(300),
    submitted_at    DATE DEFAULT SYSDATE NOT NULL,
    CONSTRAINT fk_feedback_complaint FOREIGN KEY (complaint_id) REFERENCES Complaints(complaint_id),
    CONSTRAINT uq_feedback_complaint UNIQUE (complaint_id)
);

-- One row for every status a complaint has passed through.
-- Filled by a trigger (section 8), so the application never writes to it.
CREATE TABLE Complaint_History (
    history_id      NUMBER(10) CONSTRAINT pk_history PRIMARY KEY,
    complaint_id    NUMBER(8) NOT NULL,
    status_id       NUMBER(2) NOT NULL,
    staff_id        NUMBER(5),
    changed_at      DATE DEFAULT SYSDATE NOT NULL,
    CONSTRAINT fk_history_complaint FOREIGN KEY (complaint_id) REFERENCES Complaints(complaint_id),
    CONSTRAINT fk_history_status FOREIGN KEY (status_id) REFERENCES Complaint_Status(status_id),
    CONSTRAINT fk_history_staff FOREIGN KEY (staff_id) REFERENCES Staff(staff_id)
);

CREATE SEQUENCE seq_complaint START WITH 7031 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_feedback  START WITH 8011 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_history   START WITH 1    INCREMENT BY 1 NOCACHE;

-- ============================================================================
-- 3. SAMPLE DATA
-- ============================================================================
INSERT INTO Hostels VALUES (1, 'Maple Residency',  'GIRLS', 'Dr. Meera Rao',          '9000000001');
INSERT INTO Hostels VALUES (2, 'Cedar Residency',  'BOYS',  'Mr. Arjun Das',          '9000000002');
INSERT INTO Hostels VALUES (3, 'Willow Residency', 'BOYS',  'Mr. Karthik Subramanian','9000000003');

-- Maple (girls): 101 to 105, Cedar (boys): 201 to 205, Willow (boys): 301 to 304
INSERT INTO Rooms VALUES (101, 1, 'A-101', 1, 2);
INSERT INTO Rooms VALUES (102, 1, 'A-102', 1, 3);
INSERT INTO Rooms VALUES (103, 1, 'A-205', 2, 2);
INSERT INTO Rooms VALUES (104, 1, 'A-206', 2, 2);
INSERT INTO Rooms VALUES (105, 1, 'A-310', 3, 2);
INSERT INTO Rooms VALUES (201, 2, 'B-201', 2, 2);
INSERT INTO Rooms VALUES (202, 2, 'B-202', 2, 2);
INSERT INTO Rooms VALUES (203, 2, 'B-305', 3, 3);
INSERT INTO Rooms VALUES (204, 2, 'B-306', 3, 2);
INSERT INTO Rooms VALUES (205, 2, 'B-110', 1, 2);
INSERT INTO Rooms VALUES (301, 3, 'C-104', 1, 2);
INSERT INTO Rooms VALUES (302, 3, 'C-105', 1, 2);
INSERT INTO Rooms VALUES (303, 3, 'C-212', 2, 3);
INSERT INTO Rooms VALUES (304, 3, 'C-318', 3, 2);

INSERT INTO Students VALUES (24010001, 'Aarav Sharma',    'aarav.sharma2024@vitstudent.ac.in',    '9000010001', 201);
INSERT INTO Students VALUES (24010002, 'Diya Nair',       'diya.nair2024@vitstudent.ac.in',       '9000010002', 102);
INSERT INTO Students VALUES (24010003, 'Kabir Mehta',     'kabir.mehta2024@vitstudent.ac.in',     '9000010003', 202);
INSERT INTO Students VALUES (24010004, 'Ananya Iyer',     'ananya.iyer2024@vitstudent.ac.in',     '9000010004', 101);
INSERT INTO Students VALUES (24010005, 'Ishaan Roy',      'ishaan.roy2024@vitstudent.ac.in',      '9000010005', 203);
INSERT INTO Students VALUES (24010006, 'Meghna Pillai',   'meghna.pillai2024@vitstudent.ac.in',   '9000010006', 101);
INSERT INTO Students VALUES (24010007, 'Sneha Reddy',     'sneha.reddy2024@vitstudent.ac.in',     '9000010007', 102);
INSERT INTO Students VALUES (24010008, 'Priya Menon',     'priya.menon2024@vitstudent.ac.in',     '9000010008', 103);
INSERT INTO Students VALUES (24010009, 'Tanvi Kulkarni',  'tanvi.kulkarni2024@vitstudent.ac.in',  '9000010009', 103);
INSERT INTO Students VALUES (24010010, 'Ritika Banerjee', 'ritika.banerjee2024@vitstudent.ac.in', '9000010010', 104);
INSERT INTO Students VALUES (24010011, 'Harini Venkat',   'harini.venkat2024@vitstudent.ac.in',   '9000010011', 105);
INSERT INTO Students VALUES (24010012, 'Rohan Das',       'rohan.das2024@vitstudent.ac.in',       '9000010012', 201);
INSERT INTO Students VALUES (24010013, 'Vikram Singh',    'vikram.singh2024@vitstudent.ac.in',    '9000010013', 202);
INSERT INTO Students VALUES (24010014, 'Arjun Nambiar',   'arjun.nambiar2024@vitstudent.ac.in',   '9000010014', 203);
INSERT INTO Students VALUES (24010015, 'Siddharth Rao',   'siddharth.rao2024@vitstudent.ac.in',   '9000010015', 204);
INSERT INTO Students VALUES (24010016, 'Naveen Kumar',    'naveen.kumar2024@vitstudent.ac.in',    '9000010016', 205);
INSERT INTO Students VALUES (24010017, 'Farhan Sheikh',   'farhan.sheikh2024@vitstudent.ac.in',   '9000010017', 301);
INSERT INTO Students VALUES (24010018, 'Karthik Raman',   'karthik.raman2024@vitstudent.ac.in',   '9000010018', 301);
INSERT INTO Students VALUES (24010019, 'Dev Patel',       'dev.patel2024@vitstudent.ac.in',       '9000010019', 302);
INSERT INTO Students VALUES (24010020, 'Abhishek Jain',   'abhishek.jain2024@vitstudent.ac.in',   '9000010020', 303);

INSERT INTO Staff VALUES (501, 'Ravi Kumar',    'Electrician',        '9111100001', 'AVAILABLE');
INSERT INTO Staff VALUES (502, 'Sana Joseph',   'Plumber',            '9111100002', 'AVAILABLE');
INSERT INTO Staff VALUES (503, 'Manoj Singh',   'Carpenter',          '9111100003', 'BUSY');
INSERT INTO Staff VALUES (504, 'Neha Das',      'General Maintenance','9111100004', 'AVAILABLE');
INSERT INTO Staff VALUES (505, 'Imran Khan',    'Electrician',        '9111100005', 'AVAILABLE');
INSERT INTO Staff VALUES (506, 'Lakshmi Devi',  'Housekeeping',       '9111100006', 'AVAILABLE');
INSERT INTO Staff VALUES (507, 'Faisal Ahmed',  'Network Technician', '9111100007', 'AVAILABLE');
INSERT INTO Staff VALUES (508, 'Joseph Mathew', 'Plumber',            '9111100008', 'OFF_DUTY');

INSERT INTO Categories VALUES (1, 'ELECTRICAL', 'Lights, switches, fans, and power points',    'Electrician');
INSERT INTO Categories VALUES (2, 'PLUMBING',   'Taps, pipes, drains, and water supply',       'Plumber');
INSERT INTO Categories VALUES (3, 'FURNITURE',  'Beds, desks, chairs, and cupboards',          'Carpenter');
INSERT INTO Categories VALUES (4, 'CLEANING',   'Sanitation and common-area cleanliness',      'Housekeeping');
INSERT INTO Categories VALUES (5, 'NETWORK',    'Hostel Wi-Fi or network access',              'Network Technician');
INSERT INTO Categories VALUES (6, 'CIVIL',      'Doors, windows, walls, and ceilings',         'General Maintenance');

INSERT INTO Complaint_Status VALUES (1, 'SUBMITTED');
INSERT INTO Complaint_Status VALUES (2, 'ASSIGNED');
INSERT INTO Complaint_Status VALUES (3, 'IN_PROGRESS');
INSERT INTO Complaint_Status VALUES (4, 'RESOLVED');
INSERT INTO Complaint_Status VALUES (5, 'CLOSED');

-- Complaints: id, student, category, status, staff, room, title, description, priority, created, resolved
INSERT INTO Complaints VALUES (7001, 24010001, 1, 3, 501,  201, 'Ceiling fan not working',       'Fan does not start despite switch being on.',                'HIGH',   SYSDATE-4,  NULL);
INSERT INTO Complaints VALUES (7002, 24010002, 2, 2, 502,  102, 'Washbasin leakage',             'Water is leaking below the washbasin.',                      'MEDIUM', SYSDATE-3,  NULL);
INSERT INTO Complaints VALUES (7003, 24010003, 3, 4, 503,  202, 'Broken study chair',            'One leg of the chair is unstable.',                          'LOW',    SYSDATE-8,  SYSDATE-6);
INSERT INTO Complaints VALUES (7004, 24010004, 1, 1, NULL, 101, 'Room light flickering',         'Main light flickers intermittently.',                        'URGENT', SYSDATE-1,  NULL);
INSERT INTO Complaints VALUES (7005, 24010005, 4, 5, 506,  203, 'Bathroom cleaning request',     'Requesting a detailed cleaning of the bathroom.',            'LOW',    SYSDATE-10, SYSDATE-9);
INSERT INTO Complaints VALUES (7006, 24010006, 2, 5, 502,  101, 'Flush tank not filling',        'Flush tank takes very long to fill and keeps running.',      'MEDIUM', SYSDATE-14, SYSDATE-12);
INSERT INTO Complaints VALUES (7007, 24010007, 1, 4, 505,  102, 'Socket near bed has no power',  'Charging socket has been dead since morning.',               'MEDIUM', SYSDATE-9,  SYSDATE-7);
INSERT INTO Complaints VALUES (7008, 24010008, 3, 5, 503,  103, 'Cupboard door off its hinge',   'Top cupboard door hangs loose and will not close.',          'LOW',    SYSDATE-18, SYSDATE-15);
INSERT INTO Complaints VALUES (7009, 24010009, 5, 3, 507,  103, 'Wi-Fi drops in room',           'No signal on the Wi-Fi in the evenings after 7 pm.',         'HIGH',   SYSDATE-5,  NULL);
INSERT INTO Complaints VALUES (7010, 24010010, 4, 1, NULL, 104, 'Washroom not cleaned',          'Washroom on the second floor has not been cleaned for two days.', 'MEDIUM', SYSDATE-1, NULL);
INSERT INTO Complaints VALUES (7011, 24010011, 1, 5, 501,  105, 'Tube light replacement',        'Tube light burnt out, room is dark at night.',               'MEDIUM', SYSDATE-20, SYSDATE-19);
INSERT INTO Complaints VALUES (7012, 24010012, 6, 4, 504,  201, 'Window latch broken',           'Window will not lock and rain comes in.',                    'HIGH',   SYSDATE-7,  SYSDATE-5);
INSERT INTO Complaints VALUES (7013, 24010013, 2, 3, 502,  202, 'Low water pressure',            'Water pressure is very low in the bathroom tap and shower.', 'MEDIUM', SYSDATE-2,  NULL);
INSERT INTO Complaints VALUES (7014, 24010014, 5, 2, 507,  203, 'LAN port not working',          'Ethernet port on the wall gives no connection.',             'MEDIUM', SYSDATE-2,  NULL);
INSERT INTO Complaints VALUES (7015, 24010015, 1, 5, 501,  204, 'Fan regulator sparking',        'Regulator makes a buzzing sound and sparks.',                'URGENT', SYSDATE-12, SYSDATE-11);
INSERT INTO Complaints VALUES (7016, 24010016, 6, 1, NULL, 205, 'Ceiling paint peeling',         'Paint is peeling over the bed and flakes fall down.',        'LOW',    SYSDATE-2,  NULL);
INSERT INTO Complaints VALUES (7017, 24010017, 1, 4, 505,  301, 'Switchboard loose',             'Switchboard near the desk is hanging out of the wall.',      'HIGH',   SYSDATE-6,  SYSDATE-4);
INSERT INTO Complaints VALUES (7018, 24010018, 3, 3, 503,  301, 'Bed frame creaking',            'Bed frame creaks and shakes when anyone sits on it.',        'MEDIUM', SYSDATE-6,  NULL);
INSERT INTO Complaints VALUES (7019, 24010019, 2, 5, 508,  302, 'Drain blocked',                 'Bathroom drain is blocked and water is overflowing.',        'HIGH',   SYSDATE-16, SYSDATE-14);
INSERT INTO Complaints VALUES (7020, 24010020, 4, 4, 506,  303, 'Pest spray needed',             'Cockroaches in the corner near the bathroom.',               'MEDIUM', SYSDATE-8,  SYSDATE-6);
INSERT INTO Complaints VALUES (7021, 24010002, 5, 5, 507,  102, 'Slow internet speed',           'Speed drops below 1 Mbps during the day.',                   'LOW',    SYSDATE-22, SYSDATE-19);
INSERT INTO Complaints VALUES (7022, 24010001, 3, 1, NULL, 201, 'Desk drawer stuck',             'Drawer cannot be pulled out fully.',                         'LOW',    SYSDATE-1,  NULL);
INSERT INTO Complaints VALUES (7023, 24010004, 2, 2, 502,  101, 'Tap dripping in washroom',      'Tap keeps dripping even when closed.',                       'LOW',    SYSDATE-2,  NULL);
INSERT INTO Complaints VALUES (7024, 24010013, 1, 5, 505,  202, 'Socket sparks with lamp',       'Socket sparks when plugging in a table lamp.',               'URGENT', SYSDATE-25, SYSDATE-24);
INSERT INTO Complaints VALUES (7025, 24010006, 4, 5, 506,  101, 'Dustbin not cleared',           'Corridor dustbin has not been emptied since Monday.',        'LOW',    SYSDATE-13, SYSDATE-12);
INSERT INTO Complaints VALUES (7026, 24010011, 2, 4, 502,  105, 'Shower head broken',            'Shower head cracked and sprays sideways.',                   'MEDIUM', SYSDATE-6,  SYSDATE-4);
INSERT INTO Complaints VALUES (7027, 24010016, 1, 3, 501,  205, 'Exhaust fan noisy',             'Exhaust fan rattles loudly at night.',                       'LOW',    SYSDATE-3,  NULL);
INSERT INTO Complaints VALUES (7028, 24010007, 6, 5, 504,  102, 'Door lock stiff',               'Door lock needs a lot of force to turn.',                    'MEDIUM', SYSDATE-17, SYSDATE-15);
INSERT INTO Complaints VALUES (7029, 24010019, 5, 1, NULL, 302, 'Router light red',              'Floor router has shown a red light since last night.',       'HIGH',   SYSDATE-1,  NULL);
INSERT INTO Complaints VALUES (7030, 24010008, 1, 2, 505,  103, 'Power point loose',             'Plug keeps slipping out of the socket.',                     'MEDIUM', SYSDATE-1,  NULL);

INSERT INTO Feedback VALUES (8001, 7003, 5, 'Resolved quickly and professionally.',      SYSDATE-5);
INSERT INTO Feedback VALUES (8002, 7005, 4, 'Issue handled satisfactorily.',             SYSDATE-8);
INSERT INTO Feedback VALUES (8003, 7006, 3, 'Fixed, but I had to remind twice.',         SYSDATE-11);
INSERT INTO Feedback VALUES (8004, 7008, 5, 'Cupboard door works like new.',             SYSDATE-14);
INSERT INTO Feedback VALUES (8005, 7011, 4, 'Done the next morning.',                    SYSDATE-18);
INSERT INTO Feedback VALUES (8006, 7015, 5, 'Quick action on a risky fault.',            SYSDATE-10);
INSERT INTO Feedback VALUES (8007, 7019, 2, 'Drain blocked again after two days.',       SYSDATE-13);
INSERT INTO Feedback VALUES (8008, 7021, 3, 'Speed is better but still drops at night.', SYSDATE-18);
INSERT INTO Feedback VALUES (8009, 7024, 5, 'Replaced the socket the same day.',         SYSDATE-23);
INSERT INTO Feedback VALUES (8010, 7028, 4, 'Lock works smoothly now.',                  SYSDATE-14);

COMMIT;

-- The complaints above were loaded with their final status, so rebuild the
-- history from the dates: submitted, assigned 3 hours later, in progress at the
-- midpoint (or one day in), resolved at resolved_at, closed 12 hours after that.
BEGIN
  FOR c IN (SELECT complaint_id, status_id, staff_id, created_at, resolved_at FROM Complaints) LOOP
    INSERT INTO Complaint_History VALUES (seq_history.NEXTVAL, c.complaint_id, 1, NULL, c.created_at);
    IF c.status_id >= 2 THEN
      INSERT INTO Complaint_History VALUES (seq_history.NEXTVAL, c.complaint_id, 2, c.staff_id, c.created_at + 3/24);
    END IF;
    IF c.status_id >= 3 THEN
      INSERT INTO Complaint_History VALUES (seq_history.NEXTVAL, c.complaint_id, 3, c.staff_id,
             CASE WHEN c.resolved_at IS NULL THEN c.created_at + 1
                  ELSE c.created_at + (c.resolved_at - c.created_at) / 2 END);
    END IF;
    IF c.status_id >= 4 THEN
      INSERT INTO Complaint_History VALUES (seq_history.NEXTVAL, c.complaint_id, 4, c.staff_id, c.resolved_at);
    END IF;
    IF c.status_id = 5 THEN
      INSERT INTO Complaint_History VALUES (seq_history.NEXTVAL, c.complaint_id, 5, NULL, c.resolved_at + 0.5);
    END IF;
  END LOOP;
  COMMIT;
END;
/

-- ============================================================================
-- 4. BASIC VERIFICATION
-- ============================================================================
PROMPT --- TABLE COUNTS ---
SELECT 'HOSTELS' AS table_name, COUNT(*) AS records FROM Hostels
UNION ALL SELECT 'ROOMS', COUNT(*) FROM Rooms
UNION ALL SELECT 'STUDENTS', COUNT(*) FROM Students
UNION ALL SELECT 'STAFF', COUNT(*) FROM Staff
UNION ALL SELECT 'CATEGORIES', COUNT(*) FROM Categories
UNION ALL SELECT 'COMPLAINT_STATUS', COUNT(*) FROM Complaint_Status
UNION ALL SELECT 'COMPLAINTS', COUNT(*) FROM Complaints
UNION ALL SELECT 'FEEDBACK', COUNT(*) FROM Feedback
UNION ALL SELECT 'COMPLAINT_HISTORY', COUNT(*) FROM Complaint_History;

-- ============================================================================
-- 5. VIEWS
-- ============================================================================
CREATE OR REPLACE VIEW V_COMPLAINT_DASHBOARD AS
SELECT c.complaint_id, s.student_name, h.hostel_name, r.room_number,
       cat.category_name, c.complaint_title, c.priority_level,
       st.status_name, NVL(ms.staff_name, 'Not Assigned') AS assigned_staff,
       c.created_at, c.resolved_at
FROM Complaints c
JOIN Students s ON c.student_id = s.student_id
JOIN Rooms r ON c.room_id = r.room_id
JOIN Hostels h ON r.hostel_id = h.hostel_id
JOIN Categories cat ON c.category_id = cat.category_id
JOIN Complaint_Status st ON c.status_id = st.status_id
LEFT JOIN Staff ms ON c.staff_id = ms.staff_id;

CREATE OR REPLACE VIEW V_STAFF_WORKLOAD AS
SELECT sf.staff_id, sf.staff_name, sf.role_name, sf.availability,
       c.complaint_id, c.complaint_title, c.priority_level, st.status_name
FROM Staff sf
JOIN Complaints c ON c.staff_id = sf.staff_id
JOIN Complaint_Status st ON c.status_id = st.status_id
WHERE c.status_id IN (2, 3);

CREATE OR REPLACE VIEW V_HOSTEL_SUMMARY AS
SELECT h.hostel_name,
       COUNT(c.complaint_id) AS total_complaints,
       COUNT(CASE WHEN c.status_id IN (1, 2, 3) THEN 1 END) AS pending_complaints,
       COUNT(CASE WHEN c.status_id IN (4, 5) THEN 1 END) AS completed_complaints
FROM Hostels h
LEFT JOIN Rooms r ON r.hostel_id = h.hostel_id
LEFT JOIN Complaints c ON c.room_id = r.room_id
GROUP BY h.hostel_name;

-- ============================================================================
-- 6. INDEXES
-- ============================================================================
CREATE INDEX idx_complaints_status ON Complaints(status_id);
CREATE INDEX idx_complaints_priority ON Complaints(priority_level);
CREATE INDEX idx_complaints_created ON Complaints(created_at);
CREATE INDEX idx_complaints_student ON Complaints(student_id);
-- Composite indexes for the two lookups the system repeats most:
-- open complaints of one category, and one staff member's active work.
CREATE INDEX idx_complaints_status_cat ON Complaints(status_id, category_id);
CREATE INDEX idx_complaints_staff_status ON Complaints(staff_id, status_id);

-- ============================================================================
-- 7. FUNCTIONS
-- ============================================================================
CREATE OR REPLACE FUNCTION staff_active_load (p_staff_id IN NUMBER) RETURN NUMBER IS
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM Complaints
  WHERE staff_id = p_staff_id AND status_id IN (2, 3);
  RETURN v_count;
END;
/
SHOW ERRORS

CREATE OR REPLACE FUNCTION avg_resolution_days (p_staff_id IN NUMBER) RETURN NUMBER IS
  v_avg NUMBER;
BEGIN
  SELECT AVG(resolved_at - created_at) INTO v_avg
  FROM Complaints
  WHERE staff_id = p_staff_id AND resolved_at IS NOT NULL;
  RETURN ROUND(NVL(v_avg, 0), 2);
END;
/
SHOW ERRORS

-- ============================================================================
-- 8. TRIGGERS
-- ============================================================================
-- Guard: status can only move forward, and a complaint needs a staff member
-- before it leaves SUBMITTED. Sets resolved_at when it reaches RESOLVED.
CREATE OR REPLACE TRIGGER trg_complaint_guard
BEFORE UPDATE OF status_id ON Complaints
FOR EACH ROW
BEGIN
  IF :NEW.status_id < :OLD.status_id THEN
    RAISE_APPLICATION_ERROR(-20001, 'Status cannot move backwards (from '
                            || :OLD.status_id || ' to ' || :NEW.status_id || ').');
  END IF;
  IF :NEW.status_id >= 2 AND :NEW.staff_id IS NULL THEN
    RAISE_APPLICATION_ERROR(-20002, 'Assign a staff member before changing the status.');
  END IF;
  IF :NEW.status_id >= 4 AND :NEW.resolved_at IS NULL THEN
    :NEW.resolved_at := SYSDATE;
  END IF;
END;
/
SHOW ERRORS

-- Audit: every new complaint and every real status change goes into the history.
CREATE OR REPLACE TRIGGER trg_complaint_history
AFTER INSERT OR UPDATE OF status_id ON Complaints
FOR EACH ROW
BEGIN
  IF INSERTING OR :OLD.status_id <> :NEW.status_id THEN
    INSERT INTO Complaint_History (history_id, complaint_id, status_id, staff_id, changed_at)
    VALUES (seq_history.NEXTVAL, :NEW.complaint_id, :NEW.status_id, :NEW.staff_id, SYSDATE);
  END IF;
END;
/
SHOW ERRORS

-- ============================================================================
-- 9. PROCEDURES
-- ============================================================================
-- Picks the AVAILABLE staff member with the matching role and the lowest
-- number of active complaints, then marks the complaint ASSIGNED.
CREATE OR REPLACE PROCEDURE assign_complaint (p_complaint_id IN NUMBER) IS
  v_role    Categories.handler_role%TYPE;
  v_status  Complaints.status_id%TYPE;
  v_staff   Staff.staff_id%TYPE;
  v_name    Staff.staff_name%TYPE;
  e_not_new  EXCEPTION;
  e_no_staff EXCEPTION;
BEGIN
  SELECT cat.handler_role, c.status_id INTO v_role, v_status
  FROM Complaints c
  JOIN Categories cat ON c.category_id = cat.category_id
  WHERE c.complaint_id = p_complaint_id;
  IF v_status <> 1 THEN
    RAISE e_not_new;
  END IF;
  BEGIN
    SELECT staff_id, staff_name INTO v_staff, v_name FROM (
      SELECT sf.staff_id, sf.staff_name
      FROM Staff sf
      WHERE sf.role_name = v_role AND sf.availability = 'AVAILABLE'
      ORDER BY staff_active_load(sf.staff_id), sf.staff_id
    ) WHERE ROWNUM = 1;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RAISE e_no_staff;
  END;
  UPDATE Complaints SET staff_id = v_staff, status_id = 2 WHERE complaint_id = p_complaint_id;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Complaint ' || p_complaint_id || ' assigned to ' || v_name || ' (' || v_role || ').');
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    DBMS_OUTPUT.PUT_LINE('Complaint ' || p_complaint_id || ' does not exist.');
  WHEN e_not_new THEN
    DBMS_OUTPUT.PUT_LINE('Complaint ' || p_complaint_id || ' is not in SUBMITTED state, nothing to assign.');
  WHEN e_no_staff THEN
    DBMS_OUTPUT.PUT_LINE('No available ' || v_role || ' right now. Complaint stays SUBMITTED.');
END;
/
SHOW ERRORS

CREATE OR REPLACE PROCEDURE update_complaint_status (p_complaint_id IN NUMBER, p_status_id IN NUMBER) IS
BEGIN
  UPDATE Complaints SET status_id = p_status_id WHERE complaint_id = p_complaint_id;
  IF SQL%ROWCOUNT = 0 THEN
    DBMS_OUTPUT.PUT_LINE('Complaint ' || p_complaint_id || ' does not exist.');
  ELSE
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Complaint ' || p_complaint_id || ' moved to status ' || p_status_id || '.');
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('Update rejected: ' || SQLERRM);
END;
/
SHOW ERRORS

-- Explicit cursor: complaints per hostel.
CREATE OR REPLACE PROCEDURE hostel_report IS
  CURSOR c_hostel IS
    SELECT h.hostel_name,
           COUNT(c.complaint_id) AS total,
           COUNT(CASE WHEN c.status_id IN (1, 2, 3) THEN 1 END) AS pending
    FROM Hostels h
    LEFT JOIN Rooms r ON r.hostel_id = h.hostel_id
    LEFT JOIN Complaints c ON c.room_id = r.room_id
    GROUP BY h.hostel_name
    ORDER BY total DESC, h.hostel_name;
BEGIN
  DBMS_OUTPUT.PUT_LINE(RPAD('Hostel', 20) || RPAD('Total', 8) || 'Pending');
  DBMS_OUTPUT.PUT_LINE(RPAD('-', 35, '-'));
  FOR rec IN c_hostel LOOP
    DBMS_OUTPUT.PUT_LINE(RPAD(rec.hostel_name, 20) || RPAD(TO_CHAR(rec.total), 8) || rec.pending);
  END LOOP;
END;
/
SHOW ERRORS

PROMPT --- OBJECT STATUS (everything should be VALID) ---
COLUMN object_name FORMAT A30
COLUMN object_type FORMAT A12
SELECT object_name, object_type, status
FROM user_objects
WHERE object_type IN ('VIEW','TRIGGER','PROCEDURE','FUNCTION')
ORDER BY object_type, object_name;

-- ============================================================================
-- 10. QUERIES
-- ============================================================================
COLUMN complaint_title FORMAT A28
COLUMN student_name    FORMAT A16
COLUMN hostel_name     FORMAT A17
COLUMN category_name   FORMAT A12
COLUMN status_name     FORMAT A12
COLUMN assigned_staff  FORMAT A14
COLUMN staff_name      FORMAT A14
COLUMN role_name       FORMAT A18
COLUMN priority_level  FORMAT A8
COLUMN email           FORMAT A38

PROMPT --- Q1. COMPLAINT TRACKER (6 table join) ---
SELECT c.complaint_id, s.student_name, h.hostel_name, r.room_number,
       cat.category_name, c.complaint_title, c.priority_level,
       st.status_name, NVL(ms.staff_name, 'Not Assigned') AS assigned_staff,
       TO_CHAR(c.created_at, 'DD-MON-YYYY') AS created_date
FROM Complaints c
JOIN Students s ON c.student_id = s.student_id
JOIN Rooms r ON c.room_id = r.room_id
JOIN Hostels h ON r.hostel_id = h.hostel_id
JOIN Categories cat ON c.category_id = cat.category_id
JOIN Complaint_Status st ON c.status_id = st.status_id
LEFT JOIN Staff ms ON c.staff_id = ms.staff_id
ORDER BY c.created_at DESC;

PROMPT --- Q2. UNRESOLVED COMPLAINTS BY PRIORITY ---
SELECT c.complaint_id, c.complaint_title, c.priority_level, st.status_name,
       s.student_name, ms.staff_name
FROM Complaints c
JOIN Students s ON c.student_id = s.student_id
JOIN Complaint_Status st ON c.status_id = st.status_id
LEFT JOIN Staff ms ON c.staff_id = ms.staff_id
WHERE st.status_name NOT IN ('RESOLVED','CLOSED')
ORDER BY CASE c.priority_level
           WHEN 'URGENT' THEN 1 WHEN 'HIGH' THEN 2
           WHEN 'MEDIUM' THEN 3 ELSE 4 END, c.created_at;

PROMPT --- Q3. COMPLAINTS BY STATUS ---
SELECT st.status_name, COUNT(c.complaint_id) AS complaint_count
FROM Complaint_Status st
LEFT JOIN Complaints c ON c.status_id = st.status_id
GROUP BY st.status_name
ORDER BY complaint_count DESC, st.status_name;

PROMPT --- Q4. COMPLAINTS BY CATEGORY ---
SELECT cat.category_name, COUNT(c.complaint_id) AS complaint_count
FROM Categories cat
LEFT JOIN Complaints c ON c.category_id = cat.category_id
GROUP BY cat.category_name
ORDER BY complaint_count DESC, cat.category_name;

PROMPT --- Q5. HAVING: categories with more than 4 complaints ---
SELECT cat.category_name, COUNT(*) AS complaint_count
FROM Complaints c JOIN Categories cat ON c.category_id = cat.category_id
GROUP BY cat.category_name
HAVING COUNT(*) > 4
ORDER BY complaint_count DESC;

PROMPT --- Q6. NESTED SUBQUERY: students with more than one complaint ---
SELECT s.student_name, s.room_id
FROM Students s
WHERE s.student_id IN (SELECT student_id FROM Complaints GROUP BY student_id HAVING COUNT(*) > 1)
ORDER BY s.student_name;

PROMPT --- Q7. CORRELATED SUBQUERY: staff with above-average active load ---
SELECT sf.staff_name, sf.role_name, staff_active_load(sf.staff_id) AS active_load
FROM Staff sf
WHERE (SELECT COUNT(*) FROM Complaints c
       WHERE c.staff_id = sf.staff_id AND c.status_id IN (2, 3))
    > (SELECT AVG(cnt) FROM (SELECT COUNT(*) AS cnt FROM Complaints
                             WHERE status_id IN (2, 3) GROUP BY staff_id))
ORDER BY active_load DESC, sf.staff_name;

PROMPT --- Q8. AVERAGE RESOLUTION DAYS BY CATEGORY ---
SELECT cat.category_name, COUNT(*) AS resolved_cases,
       ROUND(AVG(c.resolved_at - c.created_at), 1) AS avg_days
FROM Complaints c JOIN Categories cat ON c.category_id = cat.category_id
WHERE c.resolved_at IS NOT NULL
GROUP BY cat.category_name
ORDER BY avg_days DESC;

PROMPT --- Q9. AVERAGE RATING PER STAFF (at least 2 rated jobs) ---
SELECT sf.staff_name, sf.role_name, COUNT(*) AS rated_jobs, ROUND(AVG(f.rating), 2) AS avg_rating
FROM Feedback f
JOIN Complaints c ON f.complaint_id = c.complaint_id
JOIN Staff sf ON c.staff_id = sf.staff_id
GROUP BY sf.staff_name, sf.role_name
HAVING COUNT(*) >= 2
ORDER BY avg_rating DESC;

PROMPT --- Q10. UNION: students who reported ELECTRICAL or PLUMBING faults ---
SELECT s.student_name FROM Students s JOIN Complaints c ON c.student_id = s.student_id
JOIN Categories cat ON c.category_id = cat.category_id WHERE cat.category_name = 'ELECTRICAL'
UNION
SELECT s.student_name FROM Students s JOIN Complaints c ON c.student_id = s.student_id
JOIN Categories cat ON c.category_id = cat.category_id WHERE cat.category_name = 'PLUMBING'
ORDER BY 1;

PROMPT --- Q11. INTERSECT: students who reported both ELECTRICAL and PLUMBING ---
SELECT s.student_name FROM Students s JOIN Complaints c ON c.student_id = s.student_id
JOIN Categories cat ON c.category_id = cat.category_id WHERE cat.category_name = 'ELECTRICAL'
INTERSECT
SELECT s.student_name FROM Students s JOIN Complaints c ON c.student_id = s.student_id
JOIN Categories cat ON c.category_id = cat.category_id WHERE cat.category_name = 'PLUMBING';

PROMPT --- Q12. MINUS: rooms that never raised a complaint ---
SELECT r.room_id, r.room_number FROM Rooms r
WHERE r.room_id IN (SELECT room_id FROM Rooms MINUS SELECT room_id FROM Complaints);

PROMPT --- Q13. RANK: staff ordered by completed jobs ---
SELECT sf.staff_name, sf.role_name, COUNT(c.complaint_id) AS completed_jobs,
       RANK() OVER (ORDER BY COUNT(c.complaint_id) DESC) AS rank_no
FROM Staff sf
LEFT JOIN Complaints c ON c.staff_id = sf.staff_id AND c.status_id IN (4, 5)
GROUP BY sf.staff_name, sf.role_name
ORDER BY rank_no, sf.staff_name;

PROMPT --- Q14. PENDING COMPLAINTS BY PRIORITY FOR EACH HOSTEL ---
SELECT h.hostel_name,
       SUM(CASE WHEN c.priority_level = 'URGENT' THEN 1 ELSE 0 END) AS urgent,
       SUM(CASE WHEN c.priority_level = 'HIGH'   THEN 1 ELSE 0 END) AS high,
       SUM(CASE WHEN c.priority_level = 'MEDIUM' THEN 1 ELSE 0 END) AS medium,
       SUM(CASE WHEN c.priority_level = 'LOW'    THEN 1 ELSE 0 END) AS low
FROM Complaints c
JOIN Rooms r ON c.room_id = r.room_id
JOIN Hostels h ON r.hostel_id = h.hostel_id
WHERE c.status_id IN (1, 2, 3)
GROUP BY h.hostel_name
ORDER BY h.hostel_name;

PROMPT --- Q15. COMPLAINTS OPEN MORE THAN 2 DAYS ---
SELECT complaint_id, complaint_title, priority_level, ROUND(SYSDATE - created_at) AS age_days
FROM Complaints
WHERE resolved_at IS NULL AND SYSDATE - created_at > 2
ORDER BY age_days DESC;

PROMPT --- Q16. FEEDBACK SUMMARY ---
SELECT ROUND(AVG(rating), 2) AS average_rating, COUNT(*) AS feedback_count FROM Feedback;

-- ============================================================================
-- 11. VIEW CHECKS
-- ============================================================================
PROMPT --- V1. DASHBOARD VIEW ---
SELECT complaint_id, student_name, hostel_name, category_name, priority_level, status_name
FROM V_COMPLAINT_DASHBOARD ORDER BY complaint_id;

PROMPT --- V2. STAFF WORKLOAD VIEW ---
SELECT staff_name, role_name, complaint_id, complaint_title, priority_level, status_name
FROM V_STAFF_WORKLOAD ORDER BY staff_name, complaint_id;

PROMPT --- V3. HOSTEL SUMMARY VIEW ---
SELECT * FROM V_HOSTEL_SUMMARY ORDER BY hostel_name;

PROMPT --- INDEXES ON COMPLAINTS ---
COLUMN index_name FORMAT A30
COLUMN column_name FORMAT A20
SELECT index_name, column_name, column_position
FROM user_ind_columns WHERE table_name = 'COMPLAINTS'
ORDER BY index_name, column_position;

-- ============================================================================
-- 12. PL/SQL DEMO: NEW COMPLAINT, TRIGGERS, PROCEDURES
-- ============================================================================
PROMPT --- F1. FUNCTIONS CALLED FROM SQL ---
SELECT staff_id, staff_name, staff_active_load(staff_id) AS active_load,
       avg_resolution_days(staff_id) AS avg_days_to_resolve
FROM Staff ORDER BY staff_id;

PROMPT --- P1. CURSOR PROCEDURE: HOSTEL REPORT ---
EXEC hostel_report;

PROMPT --- T1. NEW COMPLAINT (history row is written by the trigger) ---
VARIABLE new_id NUMBER
BEGIN
  SELECT seq_complaint.NEXTVAL INTO :new_id FROM dual;
  INSERT INTO Complaints (complaint_id, student_id, category_id, room_id, complaint_title, complaint_desc, priority_level)
  VALUES (:new_id, 24010004, 1, 101, 'Geyser switch not working', 'Geyser switch in the bathroom has no response.', 'HIGH');
  COMMIT;
END;
/
PRINT new_id
SELECT history_id, complaint_id, status_id, changed_at FROM Complaint_History WHERE complaint_id = :new_id ORDER BY history_id;

PROMPT --- P2. AUTO ASSIGN (picks the less loaded electrician) ---
EXEC assign_complaint(:new_id);
SELECT complaint_id, status_id, staff_id FROM Complaints WHERE complaint_id = :new_id;

PROMPT --- P3. MOVE THROUGH THE LIFECYCLE ---
EXEC update_complaint_status(:new_id, 3);
EXEC update_complaint_status(:new_id, 4);
EXEC update_complaint_status(:new_id, 5);
INSERT INTO Feedback VALUES (seq_feedback.NEXTVAL, :new_id, 5, 'Geyser switch fixed within the hour.', SYSDATE);
COMMIT;
SELECT history_id, status_id, staff_id, TO_CHAR(changed_at, 'DD-MON HH24:MI:SS') AS changed_at
FROM Complaint_History WHERE complaint_id = :new_id ORDER BY history_id;
SELECT complaint_id, status_id, resolved_at FROM Complaints WHERE complaint_id = :new_id;

PROMPT --- P4. NO CARPENTER AVAILABLE (staff 503 is BUSY) ---
EXEC assign_complaint(7022);

PROMPT --- N1. BACKWARD STATUS MOVE (expect ORA-20001) ---
EXEC update_complaint_status(7001, 1);

PROMPT --- N2. PROGRESS WITHOUT A STAFF MEMBER (expect ORA-20002) ---
EXEC update_complaint_status(7010, 3);

PROMPT --- N3. BAD PRIORITY (expect ORA-02290) ---
UPDATE Complaints SET priority_level = 'CRITICAL' WHERE complaint_id = 7004;

PROMPT --- N4. STUDENT DOES NOT EXIST (expect ORA-02291) ---
INSERT INTO Complaints (complaint_id, student_id, category_id, room_id, complaint_title, complaint_desc)
VALUES (seq_complaint.NEXTVAL, 99999999, 1, 101, 'Orphan test', 'This should fail.');

PROMPT --- N5. SECOND FEEDBACK FOR ONE COMPLAINT (expect ORA-00001) ---
INSERT INTO Feedback VALUES (seq_feedback.NEXTVAL, 7003, 4, 'Second feedback', SYSDATE);

PROMPT --- N6. RESOLVED BEFORE CREATED (expect ORA-02290) ---
UPDATE Complaints SET resolved_at = created_at - 1 WHERE complaint_id = 7003;

-- ============================================================================
-- 13. TRANSACTION CONTROL
-- ============================================================================
PROMPT --- TXN. SAVEPOINT AND ROLLBACK ---
SAVEPOINT before_change;
UPDATE Complaints SET priority_level = 'URGENT' WHERE complaint_id = 7016;
SELECT complaint_id, priority_level FROM Complaints WHERE complaint_id = 7016;
ROLLBACK TO before_change;
SELECT complaint_id, priority_level FROM Complaints WHERE complaint_id = 7016;

-- ============================================================================
-- 14. LIFECYCLE BY HAND (use during the live demo if asked)
-- ============================================================================
-- UPDATE Complaints SET status_id = 2, staff_id = 501 WHERE complaint_id = 7004;
-- UPDATE Complaints SET status_id = 3 WHERE complaint_id = 7004;
-- UPDATE Complaints SET status_id = 4 WHERE complaint_id = 7004;
-- COMMIT;
-- SELECT * FROM Complaint_History WHERE complaint_id = 7004 ORDER BY history_id;

COMMIT;
PROMPT --- IMPLEMENTATION SCRIPT FINISHED ---
