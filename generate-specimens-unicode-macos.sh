#!/bin/bash
#
# Script to generate APFS test files for testing Unicode conversions
# Requires macOS 10.13 (High Sierra) or later

EXIT_SUCCESS=0;
EXIT_FAILURE=1;

create_test_file_entries_unicode()
{
	MOUNT_POINT=$1;

	# Create a directory
	mkdir ${MOUNT_POINT}/testdir1

	set +e;

	# Create a file for Unicode characters defined in UnicodeData.txt
	for NUMBER in `cat UnicodeData.txt | sed 's/;.*$//'`;
	do
		UNICODE_CHARACTER=`printf "%08x" $(( 0x${NUMBER} ))`;

		touch `python -c "print(''.join(['${MOUNT_POINT}/testdir1/unicode_U+${UNICODE_CHARACTER}_', '${UNICODE_CHARACTER}'.decode('hex').decode('utf-32-be')]).encode('utf-8'))"` 2> /dev/null;

		if test $? -ne 0;
		then
			echo "Unsupported: 0x${UNICODE_CHARACTER}";
		fi
	done

	set -e;
}

create_test_file_entries_unicode_exhaustive()
{
	MOUNT_POINT=$1;

	# Create a directory
	mkdir ${MOUNT_POINT}/testdir1

	set +e;

	# Create a file for every supported Unicode character
	for NUMBER in `seq $(( 0x00000000 )) $(( 0x110000 ))`;
	do
		UNICODE_CHARACTER=`printf "%08x" ${NUMBER}`;

		touch `python -c "print(''.join(['${MOUNT_POINT}/testdir1/unicode_U+${UNICODE_CHARACTER}_', '${UNICODE_CHARACTER}'.decode('hex').decode('utf-32-be')]).encode('utf-8'))"` 2> /dev/null;

		if test $? -ne 0;
		then
			echo "Unsupported: 0x${UNICODE_CHARACTER}";
		fi
	done

	set -e;
}

MACOS_VERSION=`sw_vers -productVersion`;
SPECIMENS_PATH="specimens/${MACOS_VERSION}";

if ! test -f "UnicodeData.txt";
then
	echo "Missing UnicodeData.txt file.";

	exit ${EXIT_FAILURE};
fi

if test -d ${SPECIMENS_PATH};
then
	echo "Specimens directory: ${SPECIMENS_PATH} already exists.";

	exit ${EXIT_FAILURE};
fi

mkdir -p ${SPECIMENS_PATH};

set -e;

DEVICE_NUMBER=`diskutil list | grep -e '^/dev/disk' | tail -n 1 | sed 's?^/dev/disk??;s? .*$??'`;

CONTAINER_DEVICE_NUMBER=$(( ${DEVICE_NUMBER} + 1 ));
VOLUME_DEVICE_NUMBER=$(( ${DEVICE_NUMBER} + 2 ));

# Create raw disk image with APFS container and single case-insensitive volume and files for individual Unicode characters
IMAGE_NAME="apfs_single_volume_unicode_files";
IMAGE_SIZE="32M";

hdiutil create -fs 'APFS' -size ${IMAGE_SIZE} -type UDIF -volname SingleVolume ${SPECIMENS_PATH}/${IMAGE_NAME};
hdiutil attach ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;

# For older versions of hdiutil:
# hdiutil create -size ${IMAGE_SIZE} -type UDIF ${SPECIMENS_PATH}/${IMAGE_NAME};
# hdiutil attach -nomount ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;
# diskutil apfs createContainer disk${CONTAINER_DEVICE_NUMBER}s1;
# diskutil apfs addVolume disk${VOLUME_DEVICE_NUMBER} "APFS" SingleVolume;

create_test_file_entries_unicode "/Volumes/SingleVolume";

# hdiutil detach disk${VOLUME_DEVICE_NUMBER};

hdiutil detach disk${CONTAINER_DEVICE_NUMBER};

# Create raw disk image with APFS container and single case-sensitive volume and files for individual Unicode characters
IMAGE_NAME="apfs_single_volume_unicode_files_case_sensitive";
IMAGE_SIZE="32M";

hdiutil create -fs 'APFS' -size ${IMAGE_SIZE} -type UDIF -volname SingleVolume ${SPECIMENS_PATH}/${IMAGE_NAME};
hdiutil attach ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;

# For older versions of hdiutil:
# hdiutil create -size ${IMAGE_SIZE} -type UDIF ${SPECIMENS_PATH}/${IMAGE_NAME};
# hdiutil attach -nomount ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;
# diskutil apfs createContainer disk${CONTAINER_DEVICE_NUMBER}s1;
# diskutil apfs addVolume disk${VOLUME_DEVICE_NUMBER} "Case-sensitive APFS" SingleVolume;

create_test_file_entries_unicode "/Volumes/SingleVolume";

# hdiutil detach disk${VOLUME_DEVICE_NUMBER};

hdiutil detach disk${CONTAINER_DEVICE_NUMBER};

exit ${EXIT_SUCCESS};

