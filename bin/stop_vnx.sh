#!/bin/bash

SHUTDOWN_OR_DESTROY=$1
ORDER=""

if [ "${SHUTDOWN_OR_DESTROY}" = "--shutdown" ]; then
	ORDER="--shutdown"
elif [ "${SHUTDOWN_OR_DESTROY}" = "--destroy" ]; then
	ORDER="--destroy"
else
	echo ""       
    echo "ERROR: parameter not recognised"
    echo "The valid syntax is: stop_vnx.sh --[shutdown|destroy] to either shutdown the vnx scenario saving changes (shutdown) or shutting it down discarding changes (destroy)."
    exit 1
fi

echo "--"
echo "--${SHUTDOWN_OR_DESTROY} scenario..."

for file in vnx/*; do
	sudo vnx -f $file $ORDER
done