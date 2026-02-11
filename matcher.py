# matcher.py — بسيط: يحمّل KB ويطابق أحداثًا واردة (regex, case-insensitive)
import csv
import re
from typing import List, Dict, Any

KB_FILE = "KB.csv"

def load_kb():
    kb = []
    try:
        with open(KB_FILE, newline='', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                # تنظيف الحقول الأساسية
                row = {k: (v.strip() if isinstance(v, str) else v) for k,v in row.items()}
                # تأكد من وجود pattern و match_field
                pattern = row.get("pattern","")
                try:
                    row["_re"] = re.compile(pattern, re.IGNORECASE)
                except Exception:
                    row["_re"] = None
                try:
                    row["confidence"] = float(row.get("confidence") or 0)
                except:
                    row["confidence"] = 0.0
                kb.append(row)
    except FileNotFoundError:
        return []
    return kb

_KB_CACHE = None

def get_kb():
    global _KB_CACHE
    if _KB_CACHE is None:
        _KB_CACHE = load_kb()
    return _KB_CACHE

def reload_kb():
    global _KB_CACHE
    _KB_CACHE = load_kb()
    return _KB_CACHE

def match_event(ev: Dict[str, Any], min_confidence: float = 0.0) -> List[Dict[str,Any]]:
    """
    ev: dict يحتوي على الحقول مثل host, message, event_id, CommandLine, Path, Username, LocalPort, image, ...
    يعيد قائمة بالقواعد المطابقة (كل عنصر = صف KB)
    """
    matches = []
    kb = get_kb()
    # نص رسالة عام للاسترجاع
    message = str(ev.get("message","") or "")
    # نبحث في كل قاعدة
    for rule in kb:
        if rule.get("_re") is None:
            continue
        # نأخذ الحقل المراد مطابقته
        mf = (rule.get("match_field") or "").strip()
        # نجهّز القيمة للبحث: أولوية الحقل المحدد، وإلا الرسالة العامة
        value = ""
        if mf:
            value = str(ev.get(mf) or ev.get(mf.lower()) or "")
        if not value:
            value = message
        if not value:
            continue
        # محاولة التطابق
        try:
            if rule["_re"].search(value):
                if rule.get("confidence",0) >= min_confidence:
                    matches.append(rule)
        except Exception:
            # تجاهل الأخطاء في regex runtime
            continue
    return matches
