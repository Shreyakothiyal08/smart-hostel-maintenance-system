"""Builds a small SQLite copy of the database so the Flask pages can be tested
without a MySQL server. The real project database is MySQL (sql/mysql/setup.sql)
and Oracle (sql/oracle/...). Usage: python tests/make_test_db.py"""
import os, re, sqlite3

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "sql", "oracle", "Hostel_Maintenance_Oracle_SQLPlus.sql")
OUT = os.path.join(ROOT, "tests", "test.db")

SCHEMA = """
CREATE TABLE Hostels (hostel_id INTEGER PRIMARY KEY, hostel_name, hostel_type, warden_name, contact_no);
CREATE TABLE Rooms (room_id INTEGER PRIMARY KEY, hostel_id, room_number, floor_no, room_capacity);
CREATE TABLE Students (student_id INTEGER PRIMARY KEY, student_name, email, phone_no, room_id);
CREATE TABLE Staff (staff_id INTEGER PRIMARY KEY, staff_name, role_name, phone_no, availability);
CREATE TABLE Categories (category_id INTEGER PRIMARY KEY, category_name, description, handler_role);
CREATE TABLE Complaint_Status (status_id INTEGER PRIMARY KEY, status_name);
CREATE TABLE Complaints (complaint_id INTEGER PRIMARY KEY AUTOINCREMENT, student_id, category_id,
  status_id DEFAULT 1, staff_id, room_id, complaint_title, complaint_desc, priority_level DEFAULT 'MEDIUM',
  created_at DEFAULT CURRENT_TIMESTAMP, resolved_at);
CREATE TABLE Feedback (feedback_id INTEGER PRIMARY KEY AUTOINCREMENT, complaint_id UNIQUE, rating, comments,
  submitted_at DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE Complaint_History (history_id INTEGER PRIMARY KEY AUTOINCREMENT, complaint_id, status_id, staff_id,
  changed_at DEFAULT CURRENT_TIMESTAMP);
CREATE TRIGGER g1 BEFORE UPDATE ON Complaints WHEN NEW.status_id < OLD.status_id
BEGIN SELECT RAISE(ABORT, 'Status cannot move backwards.'); END;
CREATE TRIGGER g2 BEFORE UPDATE ON Complaints WHEN NEW.status_id <> OLD.status_id AND NEW.status_id >= 2 AND NEW.staff_id IS NULL
BEGIN SELECT RAISE(ABORT, 'Assign a staff member before changing the status.'); END;
CREATE TRIGGER h1 AFTER INSERT ON Complaints
BEGIN INSERT INTO Complaint_History (complaint_id, status_id, staff_id) VALUES (NEW.complaint_id, NEW.status_id, NEW.staff_id); END;
CREATE TRIGGER h2 AFTER UPDATE ON Complaints WHEN NEW.status_id <> OLD.status_id
BEGIN
  UPDATE Complaints SET resolved_at = CURRENT_TIMESTAMP WHERE complaint_id = NEW.complaint_id AND NEW.status_id >= 4 AND resolved_at IS NULL;
  INSERT INTO Complaint_History (complaint_id, status_id, staff_id) VALUES (NEW.complaint_id, NEW.status_id, NEW.staff_id);
END;
"""

def main():
    if os.path.exists(OUT):
        os.remove(OUT)
    db = sqlite3.connect(OUT)
    db.executescript(SCHEMA)
    text = open(SRC).read()
    for m in re.finditer(r"^INSERT INTO (\w+) VALUES \((.*)\);", text, re.M):
        table, vals = m.groups()
        if "NEXTVAL" in vals or ":new" in vals:
            continue
        vals = re.sub(r"SYSDATE-(\d+)", r"datetime('now','-\1 days')", vals).replace("NULL", "NULL")
        db.execute(f"INSERT INTO {table} VALUES ({vals})")
    db.commit()
    print("built", OUT, db.execute("SELECT COUNT(*) FROM Complaints").fetchone()[0], "complaints")

if __name__ == "__main__":
    main()
