#!/bin/bash
#
# Script to generate APFS test files
# Requires macOS 10.13 (High Sierra) or later

# APFS volume roles:
# B = "Preboot"
# U = "User"
# S = "System"
# R = "Recovery"
# V = "VM"

EXIT_SUCCESS=0;
EXIT_FAILURE=1;

AFSCTOOL="/usr/local/bin/afsctool";

# Checks the availability of a binary and exits if not available.
#
# Arguments:
#   a string containing the name of the binary
#
assert_availability_binary()
{
	local BINARY=$1;

	which ${BINARY} > /dev/null 2>&1;
	if test $? -ne ${EXIT_SUCCESS};
	then
		echo "Missing binary: ${BINARY}";
		echo "";

		exit ${EXIT_FAILURE};
	fi
}

create_test_file_entries()
{
	MOUNT_POINT=$1;

	# Create an empty file
	touch ${MOUNT_POINT}/emptyfile

	# Create a directory
	mkdir ${MOUNT_POINT}/testdir1

	# Create a file
	echo "My file" > ${MOUNT_POINT}/testdir1/testfile1

	# Create a hard link to a file
	ln ${MOUNT_POINT}/testdir1/testfile1 ${MOUNT_POINT}/file_hardlink1

	# Create a symbolic link to a file
	ln -s ${MOUNT_POINT}/testdir1/testfile1 ${MOUNT_POINT}/file_symboliclink1

	# Create a hard link to a directory
	# ln ${MOUNT_POINT}/testdir1 ${MOUNT_POINT}/directory_hardlink1
	# ln: ${MOUNT_POINT}/testdir1: Is a directory

	# Create a symbolic link to a directory
	ln -s ${MOUNT_POINT}/testdir1 ${MOUNT_POINT}/directory_symboliclink1

	# Create a file with a control code in the filename
	touch `printf "${MOUNT_POINT}/control_cod\x03"`

	# Create a file with an UTF-8 NFC encoded filename
	touch `printf "${MOUNT_POINT}/nfc_t\xc3\xa9stfil\xc3\xa8"`

	# Create a file with an UTF-8 NFD encoded filename
	touch `printf "${MOUNT_POINT}/nfd_te\xcc\x81stfile\xcc\x80"`

	# Create a file with an UTF-8 NFD encoded filename
	touch `printf "${MOUNT_POINT}/nfd_\xc2\xbe"`

	# Create a file with an UTF-8 NFKD encoded filename
	touch `printf "${MOUNT_POINT}/nfkd_3\xe2\x81\x844"`

	# Create a file with filename that requires case folding if
	# the file system is case-insensitive
	touch `printf "${MOUNT_POINT}/case_folding_\xc2\xb5"`

	# Create a file with a forward slash in the filename
	touch `printf "${MOUNT_POINT}/forward:slash"`

	# Create a symbolic link to a file with a forward slash in the filename
	ln -s ${MOUNT_POINT}/forward:slash ${MOUNT_POINT}/file_symboliclink2

	# Create a file with a resource fork with content
	touch ${MOUNT_POINT}/testdir1/resourcefork1
	echo "My resource fork" > ${MOUNT_POINT}/testdir1/resourcefork1/..namedfork/rsrc

	# Create a file with an extended attribute with content
	touch ${MOUNT_POINT}/testdir1/xattr1
	xattr -w myxattr1 "My 1st extended attribute" ${MOUNT_POINT}/testdir1/xattr1

	# Create a directory with an extended attribute with content
	mkdir ${MOUNT_POINT}/testdir1/xattr2
	xattr -w myxattr2 "My 2nd extended attribute" ${MOUNT_POINT}/testdir1/xattr2

	# Create a file with an extended attribute that is not stored inline
	read -d "" -n 8192 -r LARGE_XATTR_DATA < LICENSE;
	touch ${MOUNT_POINT}/testdir1/large_xattr
	xattr -w mylargexattr "${LARGE_XATTR_DATA}" ${MOUNT_POINT}/testdir1/large_xattr

	# Create a file that uses HFS+ compression (decmpfs)
	if test -x ${AFSCTOOL};
	then
		# Create a file that uses HFS+ compression (decmpfs) compression method 3
		echo "My compressed file" > ${MOUNT_POINT}/testdir1/compressed1
		${AFSCTOOL} -c -T ZLIB ${MOUNT_POINT}/testdir1/compressed1

		# Create a file that uses HFS+ compression (decmpfs) compression method 4
		ditto --nohfsCompression LICENSE ${MOUNT_POINT}/testdir1/compressed2
		${AFSCTOOL} -c -T ZLIB ${MOUNT_POINT}/testdir1/compressed2

		# Create a file that uses HFS+ compression (decmpfs) compression method 7
		echo "My compressed file" > ${MOUNT_POINT}/testdir1/compressed3
		${AFSCTOOL} -c -T LZVN ${MOUNT_POINT}/testdir1/compressed3

		# Create a file that uses HFS+ compression (decmpfs) compression method 8
		ditto --nohfsCompression LICENSE ${MOUNT_POINT}/testdir1/compressed4
		${AFSCTOOL} -c -T LZVN ${MOUNT_POINT}/testdir1/compressed4

		# Create a file that uses HFS+ compression (decmpfs) compression method 11
		# echo "My compressed file" > ${MOUNT_POINT}/testdir1/compressed5
		# ${AFSCTOOL} -c -T LZFSE ${MOUNT_POINT}/testdir1/compressed5

		# Create a file that uses HFS+ compression (decmpfs) compression method 12
		# ditto --nohfsCompression LICENSE ${MOUNT_POINT}/testdir1/compressed6
		# ${AFSCTOOL} -c -T LZFSE ${MOUNT_POINT}/testdir1/compressed6
	else
		ditto --hfsCompression LICENSE ${MOUNT_POINT}/testdir1/compressed1
	fi

	# Create a block device file
	# Need to run mknod with sudo otherwise it errors with: Operation not permitted
	sudo mknod ${MOUNT_POINT}/testdir1/blockdev1 b 24 57

	# Create a character device file
	# Need to run mknod with sudo otherwise it errors with: Operation not permitted
	sudo mknod ${MOUNT_POINT}/testdir1/chardev1 c 13 68

	# Create a whiteout (node) file
	# Need to run mknod with sudo otherwise it errors with: Operation not permitted
	# sudo mknod ${MOUNT_POINT}/testdir1/whiteout1 w
	# mknod: Invalid argument

	# Create a pipe (FIFO) file
	mkfifo ${MOUNT_POINT}/testdir1/pipe1
}

assert_availability_binary diskutil;
assert_availability_binary hdiutil;
assert_availability_binary mkfifo;
assert_availability_binary mknod;
assert_availability_binary sw_vers;

MACOS_VERSION=`sw_vers -productVersion`;
SHORT_VERSION=`echo "${MACOS_VERSION}" | sed 's/^\([0-9][0-9]*[.][0-9][0-9]*\).*$/\1/'`;

# Note that versions of Mac OS before 10.13 do not support "sort -V"
MINIMUM_VERSION=`echo "${SHORT_VERSION} 10.13" | tr ' ' '\n' | sort -n | head -n 1`;

if test "${MINIMUM_VERSION}" != "10.13";
then
	echo "Unsupported MacOS version: ${MACOS_VERSION}";

	exit ${EXIT_FAILURE};
fi

SPECIMENS_PATH="specimens/${MACOS_VERSION}";

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

# For older versions of hdiutil:

# Create raw disk image with APFS container
# IMAGE_NAME="apfs_container";
# IMAGE_SIZE="4M";

# hdiutil create -size ${IMAGE_SIZE} -type UDIF ${SPECIMENS_PATH}/${IMAGE_NAME};
# hdiutil attach -nomount ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;
# diskutil apfs createContainer disk${CONTAINER_DEVICE_NUMBER}s1;

# hdiutil detach disk${CONTAINER_DEVICE_NUMBER};

# Create raw disk image with APFS container and single case-insensitive volume
IMAGE_NAME="apfs_single_volume";
IMAGE_SIZE="4M";

hdiutil create -fs 'APFS' -size ${IMAGE_SIZE} -type UDIF -volname SingleVolume ${SPECIMENS_PATH}/${IMAGE_NAME};
hdiutil attach ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;

# For older versions of hdiutil:
# hdiutil create -size ${IMAGE_SIZE} -type UDIF ${SPECIMENS_PATH}/${IMAGE_NAME};
# hdiutil attach -nomount ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;
# diskutil apfs createContainer disk${CONTAINER_DEVICE_NUMBER}s1;
# diskutil apfs addVolume disk${VOLUME_DEVICE_NUMBER} "APFS" SingleVolume;

create_test_file_entries "/Volumes/SingleVolume";

# hdiutil detach disk${VOLUME_DEVICE_NUMBER};

hdiutil detach disk${CONTAINER_DEVICE_NUMBER};

# Create raw disk image with APFS container and single case-sensitive volume
IMAGE_NAME="apfs_single_volume_case_sensitive";
IMAGE_SIZE="4M";

hdiutil create -fs 'APFS' -size ${IMAGE_SIZE} -type UDIF -volname SingleVolume ${SPECIMENS_PATH}/${IMAGE_NAME};
hdiutil attach ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;

# For older versions of hdiutil:
# hdiutil create -size ${IMAGE_SIZE} -type UDIF ${SPECIMENS_PATH}/${IMAGE_NAME};
# hdiutil attach -nomount ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;
# diskutil apfs createContainer disk${CONTAINER_DEVICE_NUMBER}s1;
# diskutil apfs addVolume disk${VOLUME_DEVICE_NUMBER} "Case-sensitive APFS" SingleVolume;

create_test_file_entries "/Volumes/SingleVolume";

# hdiutil detach disk${VOLUME_DEVICE_NUMBER};

hdiutil detach disk${CONTAINER_DEVICE_NUMBER};

# Create raw disk image with APFS container and single case-insensitive volume and role preboot

IMAGE_NAME="apfs_single_volume_with_role_preboot";
IMAGE_SIZE="4M";

hdiutil create -fs 'APFS' -size ${IMAGE_SIZE} -type UDIF -volname SingleVolume ${SPECIMENS_PATH}/${IMAGE_NAME};
hdiutil attach ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;

# For older versions of hdiutil:
# hdiutil create -size ${IMAGE_SIZE} -type UDIF ${SPECIMENS_PATH}/${IMAGE_NAME};
# hdiutil attach -nomount ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;
# diskutil apfs createContainer disk${CONTAINER_DEVICE_NUMBER}s1;
# diskutil apfs addVolume disk${VOLUME_DEVICE_NUMBER} "APFS" SingleVolume -role B;

create_test_file_entries "/Volumes/SingleVolume";

# hdiutil detach disk${VOLUME_DEVICE_NUMBER};

hdiutil detach disk${CONTAINER_DEVICE_NUMBER};

# Create raw disk image with APFS container and single case-insensitive volume and role recovery

IMAGE_NAME="apfs_single_volume_with_role_recovery";
IMAGE_SIZE="4M";

hdiutil create -fs 'APFS' -size ${IMAGE_SIZE} -type UDIF -volname SingleVolume ${SPECIMENS_PATH}/${IMAGE_NAME};
hdiutil attach ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;

# For older versions of hdiutil:
# hdiutil create -size ${IMAGE_SIZE} -type UDIF ${SPECIMENS_PATH}/${IMAGE_NAME};
# hdiutil attach -nomount ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;
# diskutil apfs createContainer disk${CONTAINER_DEVICE_NUMBER}s1;
# diskutil apfs addVolume disk${VOLUME_DEVICE_NUMBER} "APFS" SingleVolume -role R;

create_test_file_entries "/Volumes/SingleVolume";

# hdiutil detach disk${VOLUME_DEVICE_NUMBER};

hdiutil detach disk${CONTAINER_DEVICE_NUMBER};

# Create raw disk image with APFS container and single case-insensitive volume and role VM

IMAGE_NAME="apfs_single_volume_with_role_vm";
IMAGE_SIZE="4M";

hdiutil create -fs 'APFS' -size ${IMAGE_SIZE} -type UDIF -volname SingleVolume ${SPECIMENS_PATH}/${IMAGE_NAME};
hdiutil attach ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;

# For older versions of hdiutil:
# hdiutil create -size ${IMAGE_SIZE} -type UDIF ${SPECIMENS_PATH}/${IMAGE_NAME};
# hdiutil attach -nomount ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;
# diskutil apfs createContainer disk${CONTAINER_DEVICE_NUMBER}s1;
# diskutil apfs addVolume disk${VOLUME_DEVICE_NUMBER} "APFS" SingleVolume -role V;

create_test_file_entries "/Volumes/SingleVolume";

# hdiutil detach disk${VOLUME_DEVICE_NUMBER};

hdiutil detach disk${CONTAINER_DEVICE_NUMBER};

# Create raw disk image with APFS container and single encrypted volume

IMAGE_NAME="apfs_single_volume_encrypted";
IMAGE_SIZE="4M";

hdiutil create -fs 'APFS' -size ${IMAGE_SIZE} -type UDIF -volname SingleVolume ${SPECIMENS_PATH}/${IMAGE_NAME};
hdiutil attach ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;

# For older versions of hdiutil:
# hdiutil create -size ${IMAGE_SIZE} -type UDIF ${SPECIMENS_PATH}/${IMAGE_NAME};
# hdiutil attach -nomount ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;
# diskutil apfs createContainer disk${CONTAINER_DEVICE_NUMBER}s1;
# diskutil apfs addVolume disk${VOLUME_DEVICE_NUMBER} "APFS" SingleVolume -passphrase test;

create_test_file_entries "/Volumes/SingleVolume";

# hdiutil detach disk${VOLUME_DEVICE_NUMBER};

hdiutil detach disk${CONTAINER_DEVICE_NUMBER};

for NUMBER_OF_FILES in 100 1000 10000 100000;
do
	if test ${NUMBER_OF_FILES} -eq 100000;
	then
		IMAGE_SIZE="64M";

	elif test ${NUMBER_OF_FILES} -eq 10000;
	then
		IMAGE_SIZE="8M";
	else
		IMAGE_SIZE="4M";
	fi

	# Create raw disk image with APFS container and single case-insensitive file system with many files
	IMAGE_NAME="apfs_single_volume_${NUMBER_OF_FILES}_files";

	hdiutil create -fs 'APFS' -size ${IMAGE_SIZE} -type UDIF -volname SingleVolume ${SPECIMENS_PATH}/${IMAGE_NAME};
	hdiutil attach ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;

	# For older versions of hdiutil:
	# hdiutil create -size ${IMAGE_SIZE} -type UDIF ${SPECIMENS_PATH}/${IMAGE_NAME};
	# hdiutil attach -nomount ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;
	# diskutil apfs createContainer disk${CONTAINER_DEVICE_NUMBER}s1;
	# diskutil apfs addVolume disk${VOLUME_DEVICE_NUMBER} "APFS" SingleVolume;

	create_test_file_entries "/Volumes/SingleVolume";

	# Create additional files
	for NUMBER in `seq 2 ${NUMBER_OF_FILES}`;
	do
		if test $(( ${NUMBER} % 2 )) -eq 0;
		then
			touch /Volumes/SingleVolume/testdir1/TestFile${NUMBER};
		else
			touch /Volumes/SingleVolume/testdir1/testfile${NUMBER};
		fi
	done

	# hdiutil detach disk${VOLUME_DEVICE_NUMBER};

	hdiutil detach disk${CONTAINER_DEVICE_NUMBER};

	# Create raw disk image with APFS container and single case-sensitive file system with many files
	IMAGE_NAME="apfs_single_volume_${NUMBER_OF_FILES}_files_case_sensitive";

	hdiutil create -fs 'APFS' -size ${IMAGE_SIZE} -type UDIF -volname SingleVolume ${SPECIMENS_PATH}/${IMAGE_NAME};
	hdiutil attach ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;

	# For older versions of hdiutil:
	# hdiutil create -size ${IMAGE_SIZE} -type UDIF ${SPECIMENS_PATH}/${IMAGE_NAME};
	# hdiutil attach -nomount ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;
	# diskutil apfs createContainer disk${CONTAINER_DEVICE_NUMBER}s1;
	# diskutil apfs addVolume disk${VOLUME_DEVICE_NUMBER} "Case-sensitive APFS" SingleVolume;

	create_test_file_entries "/Volumes/SingleVolume";

	# Create additional files
	for NUMBER in `seq 2 ${NUMBER_OF_FILES}`;
	do
		if test $(( ${NUMBER} % 2 )) -eq 0;
		then
			touch /Volumes/SingleVolume/testdir1/TestFile${NUMBER};
		else
			touch /Volumes/SingleVolume/testdir1/testfile${NUMBER};
		fi
	done

	# hdiutil detach disk${VOLUME_DEVICE_NUMBER};

	hdiutil detach disk${CONTAINER_DEVICE_NUMBER};
done

for NUMBER_OF_ATTRIBUTES in 100;
do
	# Create raw disk image with APFS container and single case-insensitive file system with many attributes
	IMAGE_NAME="apfs_single_volume_${NUMBER_OF_ATTRIBUTES}_attributes";

	hdiutil create -fs 'APFS' -size ${IMAGE_SIZE} -type UDIF -volname SingleVolume ${SPECIMENS_PATH}/${IMAGE_NAME};
	hdiutil attach ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;

	# For older versions of hdiutil:
	# hdiutil create -size ${IMAGE_SIZE} -type UDIF ${SPECIMENS_PATH}/${IMAGE_NAME};
	# hdiutil attach -nomount ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;
	# diskutil apfs createContainer disk${CONTAINER_DEVICE_NUMBER}s1;
	# diskutil apfs addVolume disk${VOLUME_DEVICE_NUMBER} "APFS" SingleVolume;

	create_test_file_entries "/Volumes/SingleVolume";

	# Create additional attributes
	touch /Volumes/TestVolume/testdir1/many_xattrs;

	for NUMBER in `seq 1 ${NUMBER_OF_ATTRIBUTES}`;
	do
		xattr -w "myxattr${NUMBER}" "Extended attribute: ${NUMBER}" /Volumes/TestVolume/testdir1/many_xattrs;
	done

	# hdiutil detach disk${VOLUME_DEVICE_NUMBER};

	hdiutil detach disk${CONTAINER_DEVICE_NUMBER};

	# Create raw disk image with APFS container and single case-sensitive file system with many attributes
	IMAGE_NAME="apfs_single_volume_${NUMBER_OF_ATTRIBUTES}_attributes_case_sensitive";

	hdiutil create -fs 'APFS' -size ${IMAGE_SIZE} -type UDIF -volname SingleVolume ${SPECIMENS_PATH}/${IMAGE_NAME};
	hdiutil attach ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;

	# For older versions of hdiutil:
	# hdiutil create -size ${IMAGE_SIZE} -type UDIF ${SPECIMENS_PATH}/${IMAGE_NAME};
	# hdiutil attach -nomount ${SPECIMENS_PATH}/${IMAGE_NAME}.dmg;
	# diskutil apfs createContainer disk${CONTAINER_DEVICE_NUMBER}s1;
	# diskutil apfs addVolume disk${VOLUME_DEVICE_NUMBER} "Case-sensitive APFS" SingleVolume;

	create_test_file_entries "/Volumes/SingleVolume";

	# Create additional attributes
	touch /Volumes/TestVolume/testdir1/many_xattrs;

	for NUMBER in `seq 1 ${NUMBER_OF_ATTRIBUTES}`;
	do
		xattr -w "myxattr${NUMBER}" "Extended attribute: ${NUMBER}" /Volumes/TestVolume/testdir1/many_xattrs;
	done

	# hdiutil detach disk${VOLUME_DEVICE_NUMBER};

	hdiutil detach disk${CONTAINER_DEVICE_NUMBER};
done

# TODO: Create raw disk image with APFS container and multiple volumes

# TODO: Create raw disk image with APFS container and single case-insensitive volume and snapshots

# TODO: Create raw disk image with APFS container and single encrypted volume converted from CS with FVDE

exit ${EXIT_SUCCESS};

