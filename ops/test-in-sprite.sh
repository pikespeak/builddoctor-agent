# Tests in a copy, so that the running page does not reload.
[ -d /home/sprite/app-test ] || cp -a /home/sprite/app /home/sprite/app-test
cd /home/sprite/app-test; rm -rf lib test priv/repo; tar xzf /home/sprite/app.tgz; export MIX_ENV=test
sha256sum /home/sprite/app.tgz; mix format; tar cz lib test | base64 -w0 > /home/sprite/fmt.b64
PGPASSWORD=postgres psql -q -h 127.0.0.1 -U postgres -c "drop database if exists builddoctor_test"
mix compile --warnings-as-errors 2>&1 | tail -15; mix test --cover 2>&1 | grep -vE "100.00%|Inspect|^Running|^Getting" | tail -90; sync
