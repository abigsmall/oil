#!/usr/bin/env bash
#
# Run continuous build tasks.
#
# Usage:
#   soil/worker.sh <function name>

set -o nounset
set -o pipefail
set -o errexit

REPO_ROOT=$(cd $(dirname $0)/.. && pwd)  # tsv-lib.sh uses this
readonly REPO_ROOT

source soil/common.sh
source test/tsv-lib.sh

dump-timezone() {

  # On Travis:
  #  /usr/share/zoneinfo/UTC
  # On my machine
  #  /usr/share/zoneinfo/America/Los_Angeles

  read md5 _ <<< $(md5sum /etc/localtime)
  log "md5 = $md5"
  find /usr/share/zoneinfo -type f | xargs md5sum | grep $md5
}

dump-versions() {
  set +o errexit

  set -x
  which python2
  python2 -V

  which python3
  python3 -V
}

dump-locale() {
  set -x
  # show our locale
  locale

  # show all locales
  locale -a
}

dump-hardware() {
  egrep '^(processor|model name)' /proc/cpuinfo
  echo
  egrep '^Mem' /proc/meminfo
}

dump-distro() {
  local path=/etc/lsb-release
  if test -f $path; then
    cat $path
  fi

  apt-cache policy r-base-core
}

dump-user-host() {
  echo -n 'whoami = '
  whoami
  echo

  echo "PWD = $PWD"
  echo

  echo -n 'hostname = '
  hostname
  echo

  uname -a
  echo

  who
  echo
}

dummy-tasks() {
  ### Print tasks that execute quickly

  # (task_name, script, action, result_html)
  cat <<EOF
dump-distro      soil/worker.sh dump-distro     -
dump-user-host   soil/worker.sh dump-user-host  -
dump-env         soil/worker.sh dump-env        -
dump-timezone    soil/worker.sh dump-timezone   -
dump-locale      soil/worker.sh dump-locale     -
dump-hardware    soil/worker.sh dump-hardware   -
EOF
}

pea-tasks() {
  ### Print tasks for the 'pea' build

  # We need a later version of Python 3 / MyPy both to type check and
  # to parse

  # Run py-source so we can type check generated code
  # We need to type check more than we translate

  # (task_name, script, action, result_html)
  cat <<EOF
dump-user-host      soil/worker.sh dump-user-host           -
py-source           build/dev.sh py-source                  -
check-types         pea/test.sh check-types           -
parse-all           pea/test.sh parse-all             -
EOF
}

dev-minimal-tasks() {
  ### Print tasks for the 'dev-minimal' build

  # repo overview is suggested by README.md

  # (task_name, script, action, result_html)
  cat <<EOF
dump-user-host      soil/worker.sh dump-user-host                -
build-minimal       build/dev.sh minimal                         -
repo-overview       metrics/source-code.sh overview              -
lint                test/lint.sh soil-run                        -
typecheck-slice     types/oil-slice.sh soil-run                  -
typecheck-other     types/run.sh soil-run                        -
unit                test/unit.sh soil-run                        -
stateful            test/stateful.sh soil-run                    _tmp/spec/stateful/index.html
arena               test/arena.sh soil-run                       -
parse-errors        test/parse-errors.sh soil-run-py             -
runtime-errors      test/runtime-errors.sh run-all-with-osh      -
oil-runtime-errors  test/oil-runtime-errors.sh soil-run          -
oil-spec            test/spec.sh oil-all-serial                  _tmp/spec/oil-language/oil.html
tea-spec            test/spec.sh tea-all-serial                  _tmp/spec/tea-language/tea.html
oil-large           oil_lang/run.sh soil-run                     -
tea-large           tea/run.sh soil-run                          -
link-busybox-ash    test/spec.sh link-busybox-ash                -
osh-minimal         test/spec.sh osh-minimal                     _tmp/spec/survey/osh-minimal.html
EOF
}

# Redefinition for quicker cloud debugging
DISABLED_dev-minimal-tasks() {
  cat <<EOF
build-minimal       build/dev.sh minimal          -
interactive         test/interactive.sh soil      -
EOF
}

cpp-tasks() {
  # (task_name, script, action, result_html)

  # dependencies: cpp-unit requires build/codegen.sh ast-id-lex, which requires
  # build-minimal

  # consts_gen.py needs types_asdl.py
  cat <<EOF
dump-versions    soil/worker.sh dump-versions          -
build-minimal    build/dev.sh minimal                  -
cpp-unit-all     test/cpp-unit.sh all                  -
mycpp-git        mycpp/deps.sh git-clone               -
mycpp-pip        mycpp/deps.sh pip-install             -
build-osh-eval   build/dev.sh oil-cpp                  -
osh-eval-smoke   build/native.sh osh-eval-smoke        -
compile-osh-eval build/native.sh soil-run              -
metrics          metrics/source-code.sh write-reports  _tmp/metrics/line-counts/index.html
shell-benchmarks benchmarks/auto.sh soil-run           _tmp/benchmark-data/index.html
mycpp-examples   mycpp/build.sh examples               mycpp/_ninja/index.html
parse-errors     test/parse-errors.sh soil-run-cpp     -
spec-cpp         test/spec-cpp.sh soil-run             _tmp/spec/cpp/osh-summary.html
EOF

# Notes on steps that depend on the binary:
#   compile-osh-eval: compiles a few variant of osh_eval in parallel
#   shell-benchmarks: uses _bin/cxx-opt/osh_eval.stripped
#   parse-errors: uses _bin/cxx-asan/osh_eval
#   spec-cpp: DUPLICATE work because we don't use Ninja.  Thre is a hack with CXX=gcc.

}


# TODO: Add more tests, like
# - web/table/csv2html-test.sh (needs some assertions)
tests-todo() {
  find . -name '_*' -a -prune -o -name '*-test.sh' -a -print
}

dev-all-nix-tasks() {
  ### Print tasks for the 'dev-all' build

  # (task_name, script, action, result_html)
  cat <<EOF
build-all       build/dev.sh all            -
oil-spec        test/spec.sh oil-all-serial _tmp/spec/oil-language/oil.html
osh-spec        test/spec.sh soil-run-osh   _tmp/spec/survey/osh.html
EOF
}


# https://github.com/oilshell/oil/wiki/Contributing

ovm-tarball-tasks() {
  ### Print tasks for the 'ovm-tarball' build

  # notes:
  # - dev-all needed to crawl dependencies to make tarball.
  # - The 'tour' also depends on buildings docs.
  # - 'all-markdown' could be published.
  # - build/dev.sh all does 'all-help', so we don't need it explicitly

  # (task_name, script, action, result_html)
  cat <<EOF
dump-locale       soil/worker.sh dump-locale             -
dev-all           build/dev.sh all                       -
yajl              build/dev.sh yajl-release              -
tour              build/doc.sh tour                      _release/VERSION/doc/oil-language-tour.html
all-markdown      build/doc.sh all-markdown              -
syscall-by-code   test/syscall.sh by-code                _tmp/syscall/by-code.txt
syscall-by-input  test/syscall.sh by-input               _tmp/syscall/by-input.txt
osh-spec          test/spec.sh soil-run-osh              _tmp/spec/survey/osh.html
gold              test/gold.sh soil-run                  -
osh-usage         test/osh-usage.sh soil-run             -
oshc-deps         test/oshc-deps.sh soil-run             -
make-tarball      devtools/release.sh quick-oil-tarball  _release/oil.tar
test-tarball      build/test.sh oil-tar                  -
EOF
}

# Reuse ovm-tarball container
app-tests-tasks() {
  cat <<EOF
dev-all           build/dev.sh all                        -
yajl              build/dev.sh yajl-release               -
ble-clone         test/ble.sh clone                       -
ble-build         test/ble.sh build                       -
ble-test          test/ble.sh run-tests                   -
EOF
}

# TODO: Most of these should be Ninja tasks.
# Other tests:
# find-test, xargs-test, pgen2-test, web/table/csv2html-test.sh
# Probably should start using a shell test framework too.
other-tests-tasks() {
  cat <<EOF
dump-distro            soil/worker.sh dump-distro                 -
time-test              benchmarks/time-test.sh soil-run           -
csv-concat-test        devtools/csv-concat-test.sh soil-run       -
osh2oil                test/osh2oil.sh soil-run                   -
R-test                 devtools/R-test.sh soil-run                -
xargs-test             test/other.sh xargs-test                   -
csv2html-test          test/other.sh csv2html-test                -
oil-python-symbols     metrics/source-code.sh oil-python-symbols  -
opy-python-symbols     metrics/source-code.sh opy-python-symbols  -
opyc                   test/opyc.sh soil-run                      -
opy-count-lines        opy/soil.sh count-lines                    -
test-gold              opy/soil.sh test-gold                      -
build-oil-repo         opy/soil.sh build-oil-repo                 -
regtest-compile        opy/soil.sh regtest-compile                -
regtest-verify-golden  opy/soil.sh regtest-verify-golden          -
EOF
}

run-tasks() {
  ### Run the tasks on stdin and write _tmp/soil/INDEX.tsv.
  local out_dir=$1  # should already exist

  mkdir -p $out_dir/logs

  # So we can always run benchmarks/time_.py.  TODO: Use Ninja for deps.
  build/dev.sh time-helper

  # For the later deploy step to pick up
  date +%s > $out_dir/task-run-start-time.txt

  # This data can go on the dashboard index
  local tsv=$out_dir/INDEX.tsv
  rm -f $tsv

  local status
  local max_status=0

  while read task_name script action result_html; do
    log "--- task: $task_name ---"

    local log_path=$out_dir/logs/$task_name.txt 

    # 15 minutes per task
    # One of the longest tasks is test/spec-cpp, which takes around 420 seconds
    local timeout_secs=900

    set +o errexit
    time-tsv -o $tsv --append --time-fmt '%.2f' \
      --field $task_name --field $script --field $action \
      --field $result_html -- \
      timeout $timeout_secs $script $action >$log_path 2>&1
    status=$?
    set -o errexit

    if test "$status" -gt "$max_status"; then
      max_status=$status
    fi

    # show the last line

    echo
    tsv-row status elapsed task script action result_html
    tail -n 1 $tsv
    echo
    log "status=$status max_status=$max_status"
  done

  log '--- done ---'
  ls -l $out_dir
  wc -l $out_dir/logs/*

  # This suppressed the deployment of logs, which we don't want.  So all our
  # Travis builds succeed?  But then we can't use their failure notifications
  # (which might be OK).
  if false; then
    # exit with the maximum exit code.
    awk '
    BEGIN { max = 0 }
          { if ($1 > max) { max = $1 } }
    END   { exit(max) }
    ' $tsv
  fi

  # So the deploy step can fail later
  echo $max_status > $out_dir/exit-status.txt
}

allow-job-failure() {
  # Note: soil-web will still count failures in INDEX.tsv.  This just
  # prevents Travis from failing.

  local out='_tmp/soil/exit-status.txt '
  log "*** ALLOWING JOB FAILURE by overwriting $out ***"
  echo 0 > $out
}

_run-dev-all-nix() {
  dev-all-nix-tasks | run-tasks

  allow-job-failure

  return

  # --- DEBUGGING THROUGH STDOUT ---

  # makes _tmp
  build/dev.sh all

  # So we have something to deploy
  dummy-tasks | run-tasks

  if false; then
    test/spec.sh check-shells-exist
    # this hangs because nix bash doesn't have 'compgen' apparently
    test/spec.sh builtin-completion -v -t
  fi

  test/spec.sh soil-run-osh

}

save-metadata() {
  ### Write metadata files to be saved as JSON

  # NOTE: host-shim.sh also writes image-pull-time.txt

  local job_name=$1
  local meta_dir=$2

  echo "$job_name" > $meta_dir/job-name.txt

  # command to show current branch
  # This does NOT work in detached HEAD!  Travis puts the branch in an env
  # variable, but sr.ht doesn't.
  # git rev-parse --abbrev-ref HEAD > $meta_dir/git-branch.txt

  git log -n 1 --pretty='format:%H' > $meta_dir/commit-hash.txt

  # ISO 8601 format
  # Note: this can get confused with rebases.  Two different commits can have
  # the same date.
  git log -n 1 --pretty='format:%aI' > $meta_dir/commit-date.txt

  git log -n 1 --pretty='format:%s' > $meta_dir/commit-line.txt  # "subject"
}

job-main() {
  local job_name=$1

  local out_dir=_tmp/soil

  log "job-main: running as $(whoami) in directory $PWD"
  mkdir -v -p $out_dir
  ls -l -d $out_dir

  save-metadata $job_name $out_dir

  ${job_name}-tasks | run-tasks $out_dir
}

run-dummy() { job-main 'dummy'; }

run-dev-minimal() { job-main 'dev-minimal'; }

run-other-tests() { job-main 'other-tests'; }

run-ovm-tarball() { job-main 'ovm-tarball'; }

run-pea() { job-main 'pea'; }

run-app-tests() { job-main 'app-tests'; }

run-cpp() { job-main 'cpp'; }

run-dev-all-nix() {
  ### Travis job dev-all-nix

  local job_name='dev-all-nix'
  local out_dir=_tmp/soil
  mkdir -p $out_dir/metadata
  save-metadata $job_name $out_dir/metadata

  # Run tasks the nix environment
  nix-shell \
    --argstr dev "none" \
    --argstr test "none" \
    --argstr cleanup "none" \
    --run "$0 _run-dev-all-nix"
}

"$@"
