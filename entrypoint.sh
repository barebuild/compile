#!/bin/bash
set -e
set -o pipefail

function err() {
	echo "$1" >&2
	exit $2
}

function check_parameter_validity() {
	if [[ "$1" =~ [^\-:_/\.a-zA-Z0-9] ]]; then
		err "Invalid $2"
	fi
}

RECIPE="$1"
shift

SOURCE="/app"
WANIP=${WANIP:=barebuild.com}
WANPORT=${WANPORT:=22}
CACHE_DIR="${CACHE_DIR:="/var/cache"}"

parsed=$(getopt -o "" --longoptions "cache::,quiet::,version:,target:,prefix:" --name "$0" -- "$@")
eval set -- "$parsed"
# http://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash
while true; do
	case "$1" in
		--cache|-c)
			CACHE="$2"
			CACHE="${CACHE:=yes}"
			shift 2
			;;
		--prefix|-p)
			PREFIX="$2"
			shift 2
			;;
		--quiet|-q)
			QUIET="$2"
			QUIET="${QUIET:=yes}"
			shift 2
			;;
		--version|-v)
			VERSION="$2"
			shift 2
			;;
		--target|-t)
			TARGET="$2"
			shift 2
			;;
		--)
			shift
			break
			;;
		*)
			err "Invalid arguments" 2
			;;
	esac
done

PREFIX=${PREFIX:="/usr/local"}
CACHE=${CACHE:=yes}
QUIET=${QUIET:=no}
PULL=${PULL:=yes}

if [ -z "$RECIPE" ]; then
	recipes=$(find $SOURCE/recipes -type f -perm +111 -print0 | xargs -0 -n1 basename)
	err "# please choose a recipe
$(echo $recipes)" 2
fi

if [ -z "$VERSION" ]; then
	err "No version given" 2
fi

if [ -z "$TARGET" ]; then
	err "No target given" 2
fi

check_parameter_validity "$PREFIX" "PREFIX"
check_parameter_validity "$VERSION" "VERSION"
check_parameter_validity "$TARGET" "TARGET"

recipefile="$SOURCE/recipes/$RECIPE"
if ! test -f "$recipefile" ; then
	err "Unknown recipe: '$RECIPE'" 2
fi

WORKSPACE=$(mktemp -d)
stdin=$WORKSPACE/stdin
stdout=$WORKSPACE/stdout
log=$WORKSPACE/compile.log

if [ "$RECIPE" == "custom" ]; then
	CACHE=no
	timeout -t 5 cat > $stdin || err "Can't receive data from STDIN" 2
fi

if [ "$PULL" = "no" ] || docker pull "barebuild/$TARGET" &>/dev/null ; then
	docker_image_sha=$(docker image inspect "barebuild/$TARGET" -f '{{.Id}}' || echo "")
else
	docker_image_sha=""
fi

if [ "$docker_image_sha" == "" ]; then
	err "Invalid target" 2
fi

# invalidate cache if recipe file has changed, or prefix has changed
fingerprint="$(echo "$PREFIX" "$docker_image_sha" | cat - "$recipefile" | sha512sum | cut -f 1 -d ' ')"
cachefile="${CACHE_DIR}/${TARGET/:/-}/$RECIPE/$VERSION/$fingerprint.tgz"
cp -r $SOURCE/bin $WORKSPACE
cp -r $SOURCE/recipes $WORKSPACE
touch $stdin

LOGGER=/dev/stderr
if [ "$QUIET" == "yes" ]; then
	LOGGER=/dev/null
fi

if [ "$CACHE" == "yes" -a -f "$cachefile" ] ; then
	tar -x ./compile.log -zf $cachefile -O >$LOGGER
	cat $cachefile
	exit 0
fi

if tar czf - -C $WORKSPACE . | docker run --rm -i \
	-e JOBS="${JOBS:=$MAX_CPUS}" \
	-e PREFIX="$PREFIX" \
	-e PATH="/app/bin:/bin:/usr/local/bin:/usr/bin" \
	-e VERSION="$VERSION" \
	-e QUIET="$QUIET" \
	-e CACHE="$CACHE" \
	-e WANIP="$WANIP" \
	-e WANPORT="$WANPORT" \
	-w /app \
	"barebuild/$TARGET" \
	bash -e -o pipefail -c "tar xzf - -C /app && rm -rf \"$PREFIX\" && mkdir -p \"$PREFIX\" && cat ./stdin | ./recipes/$RECIPE \"$PREFIX\" 2>&1 | indent $RECIPE | tee -a ./compile.log >&2 && cp ./compile.log \"$PREFIX/\" && tar czf - -C \"$PREFIX\" ." > $stdout 2>$LOGGER ; then
	if tar -x ./compile.log -zf $stdout -O >/dev/null ; then
		cat $stdout
		mkdir -p $(dirname $cachefile)
		mv $stdout $cachefile
	else
		err "Build failed to produce log output" 1
	fi
else
	err "Build failed" 1
fi
