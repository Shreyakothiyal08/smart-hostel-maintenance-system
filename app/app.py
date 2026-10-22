import os
from datetime import datetime
from flask import Flask, render_template, request, redirect, url_for, flash, jsonify, abort
import db

app = Flask(__name__)
app.secret_key = os.getenv("SECRET_KEY", "dev-only-key")

BASE = """
SELECT c.complaint_id, c.complaint_title, c.complaint_desc, c.priority_level, c.created_at,
       c.resolved_at, c.status_id, st.status_name, cat.category_name,
       s.student_id, s.student_name, h.hostel_name, r.room_number,
       c.staff_id, sf.staff_name
FROM Complaints c
JOIN Students s ON c.student_id = s.student_id
JOIN Rooms r ON c.room_id = r.room_id
JOIN Hostels h ON r.hostel_id = h.hostel_id
JOIN Categories cat ON c.category_id = cat.category_id
JOIN Complaint_Status st ON c.status_id = st.status_id
LEFT JOIN Staff sf ON c.staff_id = sf.staff_id
"""
PRIORITY_ORDER = ("ORDER BY CASE c.priority_level WHEN 'URGENT' THEN 1 WHEN 'HIGH' THEN 2 "
                  "WHEN 'MEDIUM' THEN 3 ELSE 4 END, c.created_at")


@app.template_filter("dt")
def fmt_dt(v):
    if not v:
        return "-"
    if isinstance(v, str):
        try:
            v = datetime.fromisoformat(v)
        except ValueError:
            return v
    return v.strftime("%d %b %Y, %H:%M")


# ---------------------------------------------------------------- home
@app.route("/")
def home():
    return render_template("home.html",
                           students=db.query("SELECT student_id, student_name FROM Students ORDER BY student_name"),
                           staff=db.query("SELECT staff_id, staff_name, role_name FROM Staff ORDER BY staff_name"))


@app.route("/go", methods=["POST"])
def go():
    role = request.form.get("role")
    if role == "student" and request.form.get("student_id"):
        return redirect(url_for("student", sid=int(request.form["student_id"])))
    if role == "staff" and request.form.get("staff_id"):
        return redirect(url_for("staff", stid=int(request.form["staff_id"])))
    if role == "admin":
        return redirect(url_for("admin"))
    flash("Pick who you are first.", "error")
    return redirect(url_for("home"))


# ---------------------------------------------------------------- student
def get_student(sid):
    rows = db.query("SELECT s.student_id, s.student_name, s.room_id, r.room_number, h.hostel_name "
                    "FROM Students s JOIN Rooms r ON s.room_id = r.room_id "
                    "JOIN Hostels h ON r.hostel_id = h.hostel_id WHERE s.student_id = %s", (sid,))
    if not rows:
        abort(404)
    return rows[0]


@app.route("/student/<int:sid>")
def student(sid):
    me = get_student(sid)
    complaints = db.query(BASE + " WHERE c.student_id = %s ORDER BY c.created_at DESC", (sid,))
    return render_template("student.html", me=me, complaints=complaints)


@app.route("/student/<int:sid>/new", methods=["GET", "POST"])
def new_complaint(sid):
    me = get_student(sid)
    cats = db.query("SELECT category_id, category_name, description FROM Categories ORDER BY category_name")
    if request.method == "POST":
        title = request.form.get("title", "").strip()
        desc = request.form.get("desc", "").strip()
        if not title or not desc:
            flash("Title and description are required.", "error")
            return render_template("new_complaint.html", me=me, cats=cats), 400
        try:
            cid = db.execute(
                "INSERT INTO Complaints (student_id, category_id, room_id, complaint_title, complaint_desc, priority_level) "
                "VALUES (%s, %s, %s, %s, %s, %s)",
                (sid, int(request.form["category_id"]), me["room_id"], title, desc,
                 request.form.get("priority", "MEDIUM")))
        except db.DBError as e:
            flash(f"Database rejected the complaint: {e}", "error")
            return render_template("new_complaint.html", me=me, cats=cats), 400
        try:
            db.assign(cid)
            flash(f"Complaint #{cid} submitted and assigned automatically.", "ok")
        except db.DBError as e:
            flash(f"Complaint #{cid} submitted. Not assigned yet: {e}", "ok")
        return redirect(url_for("complaint", cid=cid))
    return render_template("new_complaint.html", me=me, cats=cats)


# ---------------------------------------------------------------- complaint detail
@app.route("/complaint/<int:cid>")
def complaint(cid):
    rows = db.query(BASE + " WHERE c.complaint_id = %s", (cid,))
    if not rows:
        abort(404)
    history = db.query("SELECT h.changed_at, st.status_name, sf.staff_name FROM Complaint_History h "
                       "JOIN Complaint_Status st ON h.status_id = st.status_id "
                       "LEFT JOIN Staff sf ON h.staff_id = sf.staff_id "
                       "WHERE h.complaint_id = %s ORDER BY h.history_id", (cid,))
    fb = db.query("SELECT rating, comments, submitted_at FROM Feedback WHERE complaint_id = %s", (cid,))
    return render_template("complaint.html", c=rows[0], history=history, fb=fb[0] if fb else None)


@app.route("/complaint/<int:cid>/feedback", methods=["POST"])
def feedback(cid):
    try:
        db.execute("INSERT INTO Feedback (complaint_id, rating, comments) VALUES (%s, %s, %s)",
                   (cid, int(request.form["rating"]), request.form.get("comments", "").strip()[:300]))
        db.execute("UPDATE Complaints SET status_id = 5 WHERE complaint_id = %s AND status_id = 4", (cid,))
        flash("Thanks. Complaint closed.", "ok")
    except db.DBError as e:
        flash(f"Could not save feedback: {e}", "error")
    return redirect(url_for("complaint", cid=cid))


# ---------------------------------------------------------------- staff
@app.route("/staff/<int:stid>")
def staff(stid):
    rows = db.query("SELECT staff_id, staff_name, role_name, availability FROM Staff WHERE staff_id = %s", (stid,))
    if not rows:
        abort(404)
    active = db.query(BASE + " WHERE c.staff_id = %s AND c.status_id IN (2, 3) " + PRIORITY_ORDER, (stid,))
    done = db.query(BASE + " WHERE c.staff_id = %s AND c.status_id IN (4, 5) ORDER BY c.resolved_at DESC", (stid,))
    return render_template("staff.html", me=rows[0], active=active, done=done)


@app.route("/complaint/<int:cid>/status", methods=["POST"])
def set_status(cid):
    new_status = int(request.form["status_id"])
    back = request.form.get("back") or url_for("complaint", cid=cid)
    try:
        db.execute("UPDATE Complaints SET status_id = %s WHERE complaint_id = %s", (new_status, cid))
        flash(f"Complaint #{cid} updated.", "ok")
    except db.DBError as e:
        flash(f"Update rejected by the database: {e}", "error")
    return redirect(back)


# ---------------------------------------------------------------- admin
@app.route("/admin")
def admin():
    complaints = db.query(BASE + " " + PRIORITY_ORDER)
    totals = db.query("SELECT COUNT(*) AS total, "
                      "SUM(CASE WHEN status_id IN (1,2,3) THEN 1 ELSE 0 END) AS pending FROM Complaints")[0]
    rating = db.query("SELECT AVG(rating) AS avg_rating, COUNT(*) AS n FROM Feedback")[0]
    return render_template("admin.html", complaints=complaints, totals=totals, rating=rating)


@app.route("/complaint/<int:cid>/assign", methods=["POST"])
def assign(cid):
    try:
        db.assign(cid)
        flash(f"Complaint #{cid} assigned.", "ok")
    except db.DBError as e:
        flash(f"Could not assign: {e}", "error")
    return redirect(url_for("admin"))


@app.route("/api/stats")
def stats():
    by_status = db.query("SELECT st.status_name AS label, COUNT(c.complaint_id) AS n FROM Complaint_Status st "
                         "LEFT JOIN Complaints c ON c.status_id = st.status_id "
                         "GROUP BY st.status_id, st.status_name ORDER BY st.status_id")
    by_cat = db.query("SELECT cat.category_name AS label, COUNT(c.complaint_id) AS n FROM Categories cat "
                      "LEFT JOIN Complaints c ON c.category_id = cat.category_id "
                      "GROUP BY cat.category_id, cat.category_name ORDER BY n DESC, cat.category_name")
    by_hostel = db.query("SELECT h.hostel_name AS label, COUNT(c.complaint_id) AS n FROM Hostels h "
                         "LEFT JOIN Rooms r ON r.hostel_id = h.hostel_id "
                         "LEFT JOIN Complaints c ON c.room_id = r.room_id "
                         "GROUP BY h.hostel_id, h.hostel_name ORDER BY n DESC")
    return jsonify(status=by_status, category=by_cat, hostel=by_hostel)


if __name__ == "__main__":
    app.run(debug=True)
