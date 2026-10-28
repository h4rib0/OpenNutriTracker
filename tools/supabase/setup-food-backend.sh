#!/usr/bin/env bash
# Sets up upstream's multi-source food search backend (FDC + BLS) in your own
# Supabase project, via github.com/simonoppowa/OpenNutriTracker-Backend.
#
# Asks for the database user and password interactively (the password is not
# echoed and never appears on a command line), then runs the backend's
# pipeline: download -> convert -> create schema -> import.
#
# Only the backend's own tables are created/refilled (food, nutrient,
# food_summary, ...). The fork's tables (fdc_*, user_custom_meals,
# user_recipes, user_nutrient_overrides) are not touched.
#
# Usage:
#   bash tools/supabase/setup-food-backend.sh
#   BACKEND_DIR=/some/path bash tools/supabase/setup-food-backend.sh
set -euo pipefail

BACKEND_DIR="${BACKEND_DIR:-$HOME/Development/private/OpenNutriTracker-Backend}"
# Resolve the app's .env before any cd, while the script path is still valid.
ENV_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.env"

if [ ! -d "$BACKEND_DIR/.git" ]; then
  echo "==> Lade Backend-Repo nach $BACKEND_DIR"
  git clone https://github.com/simonoppowa/OpenNutriTracker-Backend.git "$BACKEND_DIR"
else
  echo "==> Aktualisiere Backend-Repo in $BACKEND_DIR"
  git -C "$BACKEND_DIR" pull --ff-only
fi

cd "$BACKEND_DIR"
if [ ! -d .venv ]; then
  echo "==> Lege Python-Umgebung an"
  python3 -m venv .venv
fi
# shellcheck disable=SC1091
. .venv/bin/activate
python -m pip install --quiet --upgrade pip
python -m pip install --quiet psycopg2-binary openpyxl requests

# Default user from the app's .env (SUPABASE_PROJECT_URL=https://<ref>.supabase.co).
PROJECT_REF=""
if [ -f "$ENV_FILE" ]; then
  PROJECT_REF="$(sed -nE 's|^SUPABASE_PROJECT_URL="?https://([a-z0-9]+)\.supabase\.co.*|\1|p' "$ENV_FILE" | head -1)"
fi
DEFAULT_USER="${PROJECT_REF:+postgres.$PROJECT_REF}"

cat <<'INFO'

Verbindungsdaten (Supabase-Dashboard -> Projekt -> "Connect" -> "Session pooler"):
  Host:      leer lassen = Region automatisch suchen
  Benutzer:  Enter = aus der .env der App
  Passwort:  das Datenbank-Passwort des Projekts

INFO
read -rp "Host [automatisch]: " DB_HOST
read -rp "Benutzer [${DEFAULT_USER:-?}]: " DB_USER
DB_USER="${DB_USER:-$DEFAULT_USER}"
if [ -z "$DB_USER" ]; then echo "Kein Benutzer angegeben."; exit 1; fi
read -rsp "Passwort: " DB_PASS
echo

# Hand the secrets to Python via the environment, never via argv. It finds
# the pooler host (trying every Supabase region when none was given), checks
# the login and prints the working connection string to the pipe only.
echo "==> Teste Verbindung"
export DB_HOST DB_USER DB_PASS
SUPABASE_DB_URL="$(python - <<'PY'
import os, sys, urllib.parse
import psycopg2

user = os.environ["DB_USER"]
password = urllib.parse.quote(os.environ["DB_PASS"], safe="")
host = os.environ.get("DB_HOST", "").strip()

regions = [
    "eu-central-1", "eu-central-2", "eu-west-1", "eu-west-2", "eu-west-3", "eu-north-1",
    "us-east-1", "us-east-2", "us-west-1", "us-west-2", "ca-central-1", "sa-east-1",
    "ap-south-1", "ap-southeast-1", "ap-southeast-2", "ap-northeast-1", "ap-northeast-2",
]
hosts = [host] if host else [f"aws-{n}-{r}.pooler.supabase.com" for n in (0, 1) for r in regions]

last_error = None
for h in hosts:
    url = f"postgresql://{user}:{password}@{h}:5432/postgres"
    try:
        conn = psycopg2.connect(url, connect_timeout=8)
    except Exception as e:
        last_error = e
        msg = str(e).lower()
        if "password authentication failed" in msg:
            sys.exit(f"Passwort falsch (Host {h}).")
        continue
    with conn, conn.cursor() as cur:
        cur.execute("select current_user")
        print(f"OK: verbunden als {cur.fetchone()[0]} ueber {h}", file=sys.stderr)
    conn.close()
    print(url)
    sys.exit(0)
sys.exit(f"Keine Verbindung moeglich. Letzter Fehler: {last_error}")
PY
)"
unset DB_PASS
export SUPABASE_DB_URL

read -rp "Import jetzt starten (FDC + BLS, dauert einige Minuten)? [j/N] " GO
case "$GO" in
  j|J|y|Y) ;;
  *) echo "Abgebrochen."; exit 0 ;;
esac

cd scripts
# run_pipeline.py reads the connection string from $SUPABASE_DB_URL.
python run_pipeline.py --source fdc bls --action all
unset SUPABASE_DB_URL

echo
echo "==> Fertig. Test in der App: Mahlzeit hinzufuegen -> z. B. 'Apfel' suchen;"
echo "    Treffer mit BLS- bzw. FDC-Chip bedeuten, dass das Backend antwortet."
