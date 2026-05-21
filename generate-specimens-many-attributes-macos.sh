#!/bin/bash
#
# Script to generate APFS test files, that contain many (extended) attributes
# Requires macOS 10.13 (High Sierra) or later

# APFS volume roles:
# B = "Preboot"
# U = "User"
# S = "System"
# R = "Recovery"
# V = "VM"

source ./shared_macos.sh

assert_availability_binary diskutil
assert_availability_binary hdiutil
assert_availability_binary mkfifo
assert_availability_binary mknod
assert_availability_binary sw_vers

MACOS_VERSION=`sw_vers -productVersion`
SHORT_VERSION=`echo "${MACOS_VERSION}" | sed 's/^\([0-9][0-9]*[.][0-9][0-9]*\).*$/\1/'`
MAJOR_VERSION=`echo "${MACOS_VERSION}" | sed 's/^\([0-9][0-9]*\).*$/\1/'`

# Note that versions of Mac OS before 10.13 do not support "sort -V"
MAXIMUM_VERSION=`echo "${MAJOR_VERSION} 10" | tr ' ' '\n' | sed 's/[.]//' | sort -rn | head -n 1`

if test "${MAXIMUM_VERSION}" == "10"
then
	MINIMUM_VERSION=`echo "${SHORT_VERSION} 10.13" | tr ' ' '\n' | sed 's/[.]//' | sort -n | head -n 1`

	if test "${MINIMUM_VERSION}" != "1013"
	then
		echo "Unsupported MacOS version: ${MACOS_VERSION}"

		exit ${EXIT_FAILURE}
	fi
fi

SPECIMENS_PATH="specimens/${MACOS_VERSION}-many-attributes"

if test -d ${SPECIMENS_PATH}
then
	echo "Specimens directory: ${SPECIMENS_PATH} already exists."

	exit ${EXIT_FAILURE}
fi

mkdir -p ${SPECIMENS_PATH}

set -e

DEVICE_NUMBER=`diskutil list | grep -e '^/dev/disk' | tail -n 1 | sed 's?^/dev/disk??;s? .*$??'`

CONTAINER_DEVICE_NUMBER=$(( ${DEVICE_NUMBER} + 1 ))
VOLUME_DEVICE_NUMBER=$(( ${DEVICE_NUMBER} + 2 ))

for NUMBER_OF_ATTRIBUTES in 100
do
	IMAGE_FILE="${SPECIMENS_PATH}/apfs_single_volume_${NUMBER_OF_ATTRIBUTES}_attributes"

	echo "Creating: case-insensitive APFS; with: ${NUMBER_OF_ATTRIBUTES} attributes"
	hdiutil create -fs 'APFS' -size "4M" -type UDIF -volname SingleVolume "${IMAGE_FILE}"
	hdiutil attach "${IMAGE_FILE}.dmg"

	# For older versions of hdiutil:
	# hdiutil create -size "4M" -type UDIF "${IMAGE_FILE}"
	# hdiutil attach -nomount "${IMAGE_FILE}.dmg"
	# diskutil apfs createContainer disk${CONTAINER_DEVICE_NUMBER}s1
	# diskutil apfs addVolume disk${VOLUME_DEVICE_NUMBER} "APFS" SingleVolume

	create_test_file_entries "/Volumes/SingleVolume"

	# Create additional attributes
	touch /Volumes/SingleVolume/testdir1/many_xattrs

	for NUMBER in `seq 1 ${NUMBER_OF_ATTRIBUTES}`
	do
		xattr -w "myxattr${NUMBER}" "Extended attribute: ${NUMBER}" /Volumes/SingleVolume/testdir1/many_xattrs
	done

	# hdiutil detach disk${VOLUME_DEVICE_NUMBER}

	# Sleep to prevent "resource busy" warning.
	sleep 3

	hdiutil detach disk${CONTAINER_DEVICE_NUMBER}

	IMAGE_FILE="${SPECIMENS_PATH}/apfs_single_volume_${NUMBER_OF_ATTRIBUTES}_attributes_case_sensitive"

	echo "Creating: case-sensitive APFS; with: ${NUMBER_OF_ATTRIBUTES} attributes"
	hdiutil create -fs 'APFS' -size "4M" -type UDIF -volname SingleVolume "${IMAGE_FILE}"
	hdiutil attach "${IMAGE_FILE}.dmg"

	# For older versions of hdiutil:
	# hdiutil create -size "4M" -type UDIF "${IMAGE_FILE}"
	# hdiutil attach -nomount "${IMAGE_FILE}.dmg"
	# diskutil apfs createContainer disk${CONTAINER_DEVICE_NUMBER}s1
	# diskutil apfs addVolume disk${VOLUME_DEVICE_NUMBER} "Case-sensitive APFS" SingleVolume

	create_test_file_entries "/Volumes/SingleVolume"

	# Create additional attributes
	touch /Volumes/SingleVolume/testdir1/many_xattrs

	for NUMBER in `seq 1 ${NUMBER_OF_ATTRIBUTES}`
	do
		xattr -w "myxattr${NUMBER}" "Extended attribute: ${NUMBER}" /Volumes/SingleVolume/testdir1/many_xattrs
	done

	# hdiutil detach disk${VOLUME_DEVICE_NUMBER}

	# Sleep to prevent "resource busy" warning.
	sleep 3

	hdiutil detach disk${CONTAINER_DEVICE_NUMBER}
done

exit ${EXIT_SUCCESS}
