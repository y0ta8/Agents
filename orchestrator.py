# orchestrator.py — minimal MVP orchestrator (Flask) with matcher integration
from flask import Flask, request, jsonify
from datetime import datetime
import json, os

# استدعاء matcher (تأكد أن matcher.py موجود في نفس المجلد)
try:
    from matcher import match_event, reload_kb
except Exception:
    # في حال matcher.py غير موجود أو خطأ بسيط، نعرّف دالة بديلة ترجع قائمة فارغة
    def match_event(ev, min_confidence=0.0):
        return []
    def reload_kb():
        return []

app = Flask(__name__)
KB_FILE = "KB.csv"
ALERTS_FILE = "alerts.json"

if not os.path.exists(ALERTS_FILE):
    with open(ALERTS_FILE, "w") as f:
        json.dump([], f)

def load_kb():
    kb = []
    if os.path.exists(KB_FILE):
        with open(KB_FILE) as f:
            lines = f.read().splitlines()
            if not lines:
                return kb
            headers = [h.strip() for h in lines[0].split(",")]
            for row in lines[1:]:
                cols = [c.strip() for c in row.split(",")]
                if len(cols) != len(headers):
                    continue
                kb.append(dict(zip(headers, cols)))
    return kb

@app.route("/api/kb", methods=["GET"])
def api_kb():
    return jsonify({"kb": load_kb()})

@app.route("/api/ingest", methods=["POST"])
def ingest():
    try:
        ev = request.get_json(force=True)
    except:
        ev = {"raw": str(request.data)}
    ev["_received_at"] = datetime.utcnow().isoformat()

    alerts = []

    # إذا أردتِ إعادة تحميل الKB تلقائياً عند كل حدث فكّي التعليق على السطر التالي:
    # reload_kb()

    # استخدم matcher لمطابقة القواعد من KB.csv
    matches = match_event(ev, min_confidence=0.0)
    for rule in matches:
        reason = f"KB match {rule.get('id')}: {rule.get('signature_type')} on {rule.get('match_field')}"
        alert = {
            "host": ev.get("host"),
            "reason": reason,
            "time": ev["_received_at"],
            "kb": rule.get("id")
        }
        # احفظ التنبيه في الملف
        with open(ALERTS_FILE, "r+") as f:
            try:
                data = json.load(f)
            except:
                data = []
            data.append(alert)
            f.seek(0)
            json.dump(data, f, indent=2)
        alerts.append(alert)

    # إن لم يوجد تطابق، نعيد استجابة عادية بدون تنبيهات
    return jsonify({"status": "ok", "alerts": alerts})

@app.route("/api/alerts", methods=["GET"])
def get_alerts():
    with open(ALERTS_FILE) as f:
        return jsonify(json.load(f))

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8443, debug=True)
