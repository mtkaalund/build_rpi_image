#!/bin/sh

machine=`uname -m`
if [ "${machine}" != "armv7l" ]; then
	echo "This script should only be executed in a raspbian environment. Current environment is ${machine}."
	exit 1
fi

bash
