#!/bin/bash
# Read-only diagnostic. Answers one question: how does the dataset-helper code
# now shipping inside ClimWeb core relate to the tables the old plugin created?
#
# Touches nothing. Run from the climweb-docker directory:
#   bash scripts/check-dataset-helper.sh
#
# The old plugin (github.com/fgg-consultant/dataset-helper-plugin) owns app label
# `dataset_helper_plugin`, 23 migrations, and three models: PluginSettings,
# CatalogState, CatalogEntry. Do NOT run the plugin's uninstall.sh -- it calls
# `climweb migrate dataset_helper_plugin zero`, which DROPS those tables.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

set -a
# shellcheck disable=SC1091
source .env
set +a

TARGET_IMAGE="ghcr.io/wmo-raf/climweb:v${CLIMWEB_VERSION}"

echo "======================================================================"
echo " 1. Does the image ship dataset-helper code, and under what app label?"
echo "    image: $TARGET_IMAGE"
echo "======================================================================"
docker run --rm --entrypoint sh "$TARGET_IMAGE" -c '
  echo "--- files mentioning dataset_helper / CatalogEntry ---"
  grep -rl "dataset_helper\|CatalogEntry\|CatalogState" / \
       --include="*.py" 2>/dev/null \
    | grep -v "/proc/" | head -30
  echo
  echo "--- app labels declared by those apps ---"
  for f in $(grep -rl "CatalogEntry" / --include="apps.py" 2>/dev/null | head -10); do
    echo "[$f]"; grep -E "name *=|label *=" "$f"
  done
' 2>&1 | sed 's/^/  /'

echo
echo "======================================================================"
echo " 2. What is already in the database?"
echo "======================================================================"
PSQL=(docker compose exec -T climweb_db psql -U "$CMS_DB_USER" -d "$CMS_DB_NAME" -qAt)

echo "--- migration history, any app matching 'dataset' or 'catalog' ---"
"${PSQL[@]}" -c "
  select app || '  (' || count(*) || ' applied, latest: ' || max(name) || ')'
  from django_migrations
  where app ilike '%dataset%' or app ilike '%catalog%' or app ilike '%helper%'
  group by app order by app;" 2>&1 | sed 's/^/  /'

echo
echo "--- tables belonging to the old plugin ---"
"${PSQL[@]}" -c "
  select tablename
  from pg_tables
  where tablename like 'dataset_helper_plugin%'
  order by tablename;" 2>&1 | sed 's/^/  /'

echo
echo "--- rows at stake ---"
for t in dataset_helper_plugin_catalogentry \
         dataset_helper_plugin_catalogstate \
         dataset_helper_plugin_pluginsettings; do
  n=$("${PSQL[@]}" -c "select count(*) from $t;" 2>/dev/null) \
    && echo "  $t: ${n:-?} rows" \
    || echo "  $t: (table absent)"
done

echo
echo "======================================================================"
echo " 3. Is the plugin still on disk / still loaded?"
echo "======================================================================"
echo "--- CLIMWEB_PLUGIN_GIT_REPOS in .env ---"
grep -E "^CLIMWEB_PLUGIN_GIT_REPOS=" .env | sed 's/^/  /'
echo "--- plugin directory (bind-mounted to /climweb/user-plugins) ---"
ls -1 "${CLIMWEB_PLUGIN_DIR:-./climweb/plugins}" 2>/dev/null | sed 's/^/  /' \
  || echo "  (empty or missing)"
echo "--- apps the RUNNING container actually loaded ---"
docker compose exec -T climweb sh -c \
  'climweb shell -c "
from django.apps import apps
for a in apps.get_app_configs():
    if any(k in a.label.lower() for k in (\"dataset\",\"catalog\",\"helper\")):
        print(a.label, \"->\", a.name)
"' 2>&1 | sed 's/^/  /'

echo
echo "======================================================================"
echo " HOW TO READ THIS"
echo "======================================================================"
cat <<'EOF'
  Section 1 empty, or no CatalogEntry in the image
      The integration is not in this version. Check CLIMWEB_VERSION -- .env
      pins 1.1.5 while .env.sample ships 1.1.6. Removing the plugin now would
      remove the feature outright. Bump the version first.

  Section 1 shows app label `dataset_helper_plugin`
      Core adopted the label and the migration history. Delete the plugin
      directory and leave the database alone -- core takes over the tables.

  Section 1 shows a DIFFERENT label (e.g. `dataset_helper`)
      Two apps, two sets of tables. The row counts in section 2 tell you how
      much data needs copying across before the old tables are dropped. Do
      this with a data migration or a SQL INSERT..SELECT, not by hand.

  Section 3 still lists dataset_helper_plugin
      Clearing CLIMWEB_PLUGIN_GIT_REPOS is not sufficient on its own: the
      plugin directory is bind-mounted and scanned on start, so the code keeps
      loading until the directory itself is removed.
EOF
