"""Common DB setup for all 4 office apps: creates each app's SQL Server
schema (if missing) and all its tables, driven entirely by config.yaml.

Run once per environment, after each app's own .env / DATABASE_URL (or
HEALTHCHECK_DB_DSN for HealthCheckPlatform) already points at that
environment's SQL Server:

    python setup_database.py                 # all projects
    python setup_database.py ticket_tracker   # just one, by its config name
"""
import importlib.util
import sys
from pathlib import Path

import yaml
from sqlalchemy import text

CONFIG_PATH = Path(__file__).parent / "config.yaml"


def _load_module_from_path(module_file: Path, module_name: str):
    spec = importlib.util.spec_from_file_location(module_name, module_file)
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def _setup_flask_project(project: dict) -> None:
    project_path = Path(project["path"])
    sys.path.insert(0, str(project_path))
    module = _load_module_from_path(project_path / f"{project['db_module']}.py", project["db_module"])
    app = module.app
    db = sys.modules["db"].db  # every project's own db.py registers itself as "db"
    schema = project["schema_name"]

    uri = app.config.get("SQLALCHEMY_DATABASE_URI", "")
    if uri.startswith("sqlite:///"):
        print(f"  [{project['name']}] sqlite -- nothing to set up, create_all() runs automatically on app startup.")
        sys.path.remove(str(project_path))
        return

    with app.app_context():
        with db.engine.connect() as conn:
            exists = conn.execute(text("SELECT 1 FROM sys.schemas WHERE name = :name"), {"name": schema}).fetchone()
            if exists is None:
                conn.execute(text(f"CREATE SCHEMA {schema}"))
                conn.commit()
                print(f"  [{project['name']}] schema '{schema}' created")
            else:
                print(f"  [{project['name']}] schema '{schema}' already exists")

        db.create_all()
        insp = db.inspect(db.engine)
        tables = insp.get_table_names(schema=schema)
        print(f"  [{project['name']}] {schema} schema has {len(tables)} tables")

    sys.path.remove(str(project_path))


def _setup_raw_project(project: dict) -> None:
    # db_module looks like "raw:db.repository:init_db"
    _, module_path, func_name = project["db_module"].split(":")
    project_path = Path(project["path"])
    sys.path.insert(0, str(project_path))
    module = importlib.import_module(module_path)
    getattr(module, func_name)()
    print(f"  [{project['name']}] schema + tables created (or already existed)")
    sys.path.remove(str(project_path))


def setup_project(project: dict) -> None:
    print(f"--- {project['name']} ---")
    if project["db_module"].startswith("raw:"):
        _setup_raw_project(project)
    else:
        _setup_flask_project(project)


def main():
    with open(CONFIG_PATH, encoding="utf-8") as f:
        config = yaml.safe_load(f)

    only = sys.argv[1] if len(sys.argv) > 1 else None
    projects = config["projects"]
    if only:
        projects = [p for p in projects if p["name"] == only]
        if not projects:
            print(f"No project named '{only}' in config.yaml")
            sys.exit(1)

    for project in projects:
        setup_project(project)

    print("\nDone.")


if __name__ == "__main__":
    main()
