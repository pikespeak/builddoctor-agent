#!/bin/bash
# Runs once in the Sprite: the app gets its own role, which owns its database and is no superuser.
# So a hole in a query cannot start programs. Back: write the old address to db.url and restart the app.
set -e -o pipefail
umask 077
export PGPASSWORD=postgres
p() { psql -v ON_ERROR_STOP=1 -q -h 127.0.0.1 -U postgres "$@"; }
[ -s /home/sprite/db.url ] && { echo "db.url exists, nothing done"; exit 0; }
pw=$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')
[ ${#pw} -ge 30 ]
# The password goes through stdin, not through the arguments of a process.
{ echo "create role builddoctor login nosuperuser nocreatedb nocreaterole noreplication password '$pw';"
  echo "alter database builddoctor_dev owner to builddoctor;"; } | p postgres
p builddoctor_dev <<'SQL'
alter schema public owner to builddoctor;
do $$ declare r record; begin
  for r in select c.oid::regclass as name, c.relkind as kind from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind in ('r','S','v') loop
    if r.kind = 'S' and exists (select 1 from pg_depend d where d.objid = r.name::oid and d.deptype in ('a','i')) then continue; end if;
    execute format('alter %s %s owner to builddoctor', case r.kind when 'S' then 'sequence' when 'v' then 'view' else 'table' end, r.name);
  end loop;
  for r in select p.oid::regprocedure as name from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' loop
    execute format('alter routine %s owner to builddoctor', r.name);
  end loop;
  for r in select t.oid::regtype as name from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public' and t.typtype = 'e' loop
    execute format('alter type %s owner to builddoctor', r.name);
  end loop;
end $$;
SQL
echo "ecto://builddoctor:$pw@127.0.0.1/builddoctor_dev" > /home/sprite/db.url
export PGPASSWORD=$pw
t() { psql -At -h 127.0.0.1 -U builddoctor builddoctor_dev -c "$1" 2>&1 | head -1; }
echo "superuser: $(t 'show is_superuser')"; echo "audits: $(t 'select count(*) from audits')"
echo "program: $(t "copy (select 1) to program 'true'")"
echo "not owned: $(t "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','S') and pg_get_userbyid(c.relowner) <> 'builddoctor'")"
