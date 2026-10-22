import os
import re
import oracledb


class DBError(Exception):
    """Raised when the database rejects an operation."""


def _connect():
    try:
        return oracledb.connect(
            user=os.getenv("DB_USER", "HOSTEL_USER"),
            password=os.getenv("DB_PASSWORD", ""),
            dsn=os.getenv("DB_DSN", "localhost:1521/XEPDB1"),
        )
    except oracledb.Error as exc:
        raise DBError(str(exc)) from exc


def _convert_placeholders(sql):
    index = 0

    def replace_placeholder(match):
        nonlocal index
        index += 1
        return f":{index}"

    return re.sub(r"%s", replace_placeholder, sql)


def query(sql, args=()):
    con = _connect()
    try:
        with con.cursor() as cur:
            cur.execute(_convert_placeholders(sql), args)

            if cur.description is None:
                return []

            columns = [column[0].lower() for column in cur.description]
            return [
                dict(zip(columns, row))
                for row in cur.fetchall()
            ]

    except oracledb.Error as exc:
        raise DBError(str(exc)) from exc
    finally:
        con.close()


def execute(sql, args=()):
    con = _connect()

    try:
        with con.cursor() as cur:
            normalized = sql.strip().lower()

            if normalized.startswith("insert into complaints"):
                if len(args) != 6:
                    raise DBError(
                        "Complaint insertion requires six values."
                    )

                new_id = cur.var(oracledb.DB_TYPE_NUMBER)

                cur.execute(
                    """
                    INSERT INTO Complaints (
                        complaint_id,
                        student_id,
                        category_id,
                        room_id,
                        complaint_title,
                        complaint_desc,
                        priority_level
                    )
                    VALUES (
                        seq_complaint.NEXTVAL,
                        :1, :2, :3, :4, :5, :6
                    )
                    RETURNING complaint_id INTO :7
                    """,
                    list(args) + [new_id],
                )

                value = new_id.getvalue()
                if isinstance(value, list):
                    value = value[0]

                complaint_id = int(value)
                con.commit()
                return complaint_id

            if normalized.startswith("insert into feedback"):
                if len(args) != 3:
                    raise DBError(
                        "Feedback insertion requires three values."
                    )

                cur.execute(
                    """
                    INSERT INTO Feedback (
                        feedback_id,
                        complaint_id,
                        rating,
                        comments
                    )
                    VALUES (
                        seq_feedback.NEXTVAL,
                        :1, :2, :3
                    )
                    """,
                    args,
                )

                con.commit()
                return None

            cur.execute(_convert_placeholders(sql), args)
            con.commit()
            return None

    except DBError:
        con.rollback()
        raise
    except oracledb.Error as exc:
        con.rollback()
        raise DBError(str(exc)) from exc
    finally:
        con.close()


def assign(complaint_id):
    con = _connect()

    try:
        with con.cursor() as cur:
            cur.callproc("ASSIGN_COMPLAINT", [complaint_id])

        con.commit()

    except oracledb.Error as exc:
        con.rollback()
        raise DBError(str(exc)) from exc
    finally:
        con.close()