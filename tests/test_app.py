"""Page checks that run against the SQLite test copy. Run from the project root:
    python tests/make_test_db.py
    python tests/test_app.py
"""
import os, sys
os.environ["DB_BACKEND"] = "sqlite"
os.environ["SQLITE_PATH"] = os.path.join(os.path.dirname(os.path.abspath(__file__)), "test.db")
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "app"))
from app import app  # noqa: E402
import db  # noqa: E402

c = app.test_client()
ok = 0
def check(name, cond):
    global ok
    print(("PASS " if cond else "FAIL ") + name)
    ok += 0 if cond else 1

r = c.get("/");                       check("home page", r.status_code == 200 and b"Aarav Sharma" in r.data)
r = c.get("/student/24010001");       check("student page lists own complaints", b"Ceiling fan not working" in r.data)
r = c.get("/student/1");              check("unknown student gives 404", r.status_code == 404)
r = c.get("/admin");                  check("admin dashboard", r.status_code == 200 and b"complaints in total" in r.data)
r = c.get("/api/stats").get_json();   check("stats api totals 30", sum(x["n"] for x in r["status"]) == 30)
check("stats by category electrical = 9", [x["n"] for x in r["category"] if x["label"] == "ELECTRICAL"] == [9])

r = c.post("/student/24010004/new", data={"category_id": 1, "title": "Geyser switch", "desc": "No response", "priority": "HIGH"})
check("new complaint redirects", r.status_code == 302)
new_id = int(r.headers["Location"].rstrip("/").split("/")[-1])
row = db.query("SELECT status_id, staff_id FROM Complaints WHERE complaint_id = %s", (new_id,))[0]
check("auto assign picked Imran Khan (505, lowest electrician load)", row["status_id"] == 2 and row["staff_id"] == 505)
check("history has 1 row after insert and 1 after assign", len(db.query("SELECT * FROM Complaint_History WHERE complaint_id = %s", (new_id,))) == 2)

r = c.post(f"/complaint/{new_id}/status", data={"status_id": 1}, follow_redirects=True)
check("backward move rejected", b"cannot move backwards" in r.data)
r = c.post("/complaint/7010/status", data={"status_id": 3}, follow_redirects=True)
check("progress without staff rejected", b"Assign a staff member" in r.data)

c.post(f"/complaint/{new_id}/status", data={"status_id": 3})
c.post(f"/complaint/{new_id}/status", data={"status_id": 4})
row = db.query("SELECT status_id, resolved_at FROM Complaints WHERE complaint_id = %s", (new_id,))[0]
check("resolved sets resolved_at", row["status_id"] == 4 and row["resolved_at"])
r = c.get(f"/complaint/{new_id}");    check("feedback form shows when resolved", b"Rate it to close" in r.data)
c.post(f"/complaint/{new_id}/feedback", data={"rating": 5, "comments": "Quick"})
row = db.query("SELECT status_id FROM Complaints WHERE complaint_id = %s", (new_id,))[0]
check("feedback closes the complaint", row["status_id"] == 5)
r = c.post(f"/complaint/{new_id}/feedback", data={"rating": 4}, follow_redirects=True)
check("second feedback rejected", b"Could not save feedback" in r.data)

r = c.post("/complaint/7022/assign", follow_redirects=True)
check("no carpenter available message", b"Could not assign" in r.data)
r = c.get("/staff/505");              check("staff page", r.status_code == 200 and b"Active work" in r.data)
print("\nfailures:", ok)
sys.exit(1 if ok else 0)
