#!/bin/bash
#
# Script to generate encrypted APFS test files
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

SPECIMENS_PATH="specimens/${MACOS_VERSION}-encrypted"

if test -d ${SPECIMENS_PATH}
then
    echo "Specimens directory: ${SPECIMENS_PATH} already exists."

    exit ${EXIT_FAILURE}
fi

mkdir -p ${SPECIMENS_PATH}

set -e

# Attaches a disk image and echos the APFS physical store device.
#
# Note that the physical store device is read from the output of
# "hdiutil attach" itself, since the encryption steps below need a device while
# the image is attached. The APFS container device is a separate device that
# the caller resolves from the physical store device.
#
# Arguments:
#   a string containing the path of the disk image
#
# Returns:
#   0 on success, 1 on error. Note that errors are written to stderr, since
#   stdout carries the device to the caller.
#
attach_image()
{
    local IMAGE_PATH=$1

    local ATTACH_OUTPUT
    local PHYSICAL_STORES
    local NUMBER_OF_PHYSICAL_STORES

    # Note that the exit status of "hdiutil attach" is checked explicitly.
    # This function is called from a command substitution, where "set -e" does
    # not take effect, and the "sed" that ends the pipeline below exits with 0
    # even for empty input, so a failing attach would otherwise yield an empty
    # device and an exit status of 0.
    if ! ATTACH_OUTPUT=`hdiutil attach "${IMAGE_PATH}" -nobrowse`
    then
        echo "Unable to attach: ${IMAGE_PATH}." >&2

        return 1
    fi

    PHYSICAL_STORES=`echo "${ATTACH_OUTPUT}" | grep 'Apple_APFS' | sed 's?^/dev/??;s?[ 	].*$??'`

    if test -z "${PHYSICAL_STORES}"
    then
        echo "Unable to determine APFS physical store device of: ${IMAGE_PATH}." >&2

        return 1
    fi

    NUMBER_OF_PHYSICAL_STORES=`echo "${PHYSICAL_STORES}" | wc -l | tr -d ' '`

    if test "${NUMBER_OF_PHYSICAL_STORES}" -ne 1
    then
        echo "Unable to determine a single APFS physical store device of: ${IMAGE_PATH}, found: ${NUMBER_OF_PHYSICAL_STORES}." >&2

        return 1
    fi

    echo "${PHYSICAL_STORES}"
}

# Creates a disk image with an APFS container and a single encrypted volume.
#
# Arguments:
#   a string containing the path of the disk image, without extension
#   a string containing the name of the volume
#   a string containing the passphrase
#
create_encrypted_volume()
{
    local IMAGE_FILE=$1
    local VOLUME_NAME=$2
    local PASSPHRASE=$3

    # Note that 24M is used instead of the 4M of the unencrypted specimens,
    # since "diskutil apfs encryptVolume" needs headroom for the conversion.
    hdiutil create -fs 'APFS' -size "24M" -type UDIF -volname "${VOLUME_NAME}" -quiet "${IMAGE_FILE}"

    local PHYSICAL_STORE
    local CONTAINER_DEVICE
    local VOLUME_DEVICE
    local NUMBER_OF_CONTAINER_DEVICES
    local NUMBER_OF_VOLUME_DEVICES

    if ! PHYSICAL_STORE=`attach_image "${IMAGE_FILE}.dmg"`
    then
        exit ${EXIT_FAILURE}
    fi

    # Note that "diskutil apfs list" prints the "APFS Container Reference:"
    # line above the physical store it contains, so the 10 line window below
    # reaches back from the physical store to its own container reference
    # without reaching the preceding container. The number of matches is
    # checked explicitly below rather than assuming the window selected
    # exactly one.
    CONTAINER_DEVICE=`diskutil apfs list | grep -B 10 "${PHYSICAL_STORE}" | grep 'APFS Container Reference:' | sed 's?^.*: *??'`

    # Note that the pipelines here end in "sed", which exits with 0 for empty
    # input, so the devices are checked explicitly rather than relying on
    # their exit status. A device that is empty, or that resolved to more than
    # one match, must not reach the encryption or detach steps below, where a
    # multi-line value would word split into several arguments.
    if test -z "${CONTAINER_DEVICE}"
    then
        echo "Unable to determine APFS container device of: ${IMAGE_FILE}.dmg."

        exit ${EXIT_FAILURE}
    fi

    NUMBER_OF_CONTAINER_DEVICES=`echo "${CONTAINER_DEVICE}" | wc -l | tr -d ' '`

    if test "${NUMBER_OF_CONTAINER_DEVICES}" -ne 1
    then
        echo "Unable to determine a single APFS container device of: ${IMAGE_FILE}.dmg, found: ${NUMBER_OF_CONTAINER_DEVICES}."

        exit ${EXIT_FAILURE}
    fi

    VOLUME_DEVICE=`diskutil list "${CONTAINER_DEVICE}" | grep "${VOLUME_NAME}" | sed 's?^.*[ 	]\([a-z0-9]*\)$?\1?'`

    if test -z "${VOLUME_DEVICE}"
    then
        echo "Unable to determine APFS volume device of: ${IMAGE_FILE}.dmg."

        exit ${EXIT_FAILURE}
    fi

    NUMBER_OF_VOLUME_DEVICES=`echo "${VOLUME_DEVICE}" | wc -l | tr -d ' '`

    if test "${NUMBER_OF_VOLUME_DEVICES}" -ne 1
    then
        echo "Unable to determine a single APFS volume device of: ${IMAGE_FILE}.dmg, found: ${NUMBER_OF_VOLUME_DEVICES}."

        exit ${EXIT_FAILURE}
    fi

    create_test_file_entries "/Volumes/${VOLUME_NAME}"

    # Write a distinctive plaintext canary before conversion, so that the
    # encryption can be checked below. Without it a volume that reports
    # "FileVault: Yes" over unconverted plaintext would pass unnoticed.
    local CANARY='PLAINTEXT-CANARY-9c1f2e7b-must-not-survive-as-cleartext'

    printf '%s\n' "${CANARY}" > "/Volumes/${VOLUME_NAME}/canary.txt"
    sync

    # Check that the canary is on the volume now, so that the check after
    # conversion cannot pass because the canary was never written.
    #
    # Note that the exit status of grep is checked explicitly here for the
    # same reason as the raw image check below: grep exits with 1 if the
    # canary was not found but with a status greater than 1 if the file could
    # not be read, and a read error must not be reported as a failed write.
    local CANARY_GREP_EXIT_STATUS=0

    grep -a -q "${CANARY}" "/Volumes/${VOLUME_NAME}/canary.txt" || CANARY_GREP_EXIT_STATUS=$?

    if test ${CANARY_GREP_EXIT_STATUS} -gt 1
    then
        echo "Unable to read back the plaintext canary from: /Volumes/${VOLUME_NAME}/canary.txt."

        exit ${EXIT_FAILURE}
    fi

    if test ${CANARY_GREP_EXIT_STATUS} -ne 0
    then
        echo "Unable to write plaintext canary before encryption."

        exit ${EXIT_FAILURE}
    fi

    diskutil apfs encryptVolume "${VOLUME_DEVICE}" -user disk -passphrase "${PASSPHRASE}"

    # Encryption runs in the background, so wait for it to complete.
    #
    # While conversion is ongoing "diskutil apfs list" shows an
    # "Encryption Progress: NN.0%" line for the volume in place of its
    # "FileVault:" line. The two were never observed together. The presence of
    # progress line, not its contents, is what indicates that conversion is
    # unfinished. Note that "Conversion Progress" is the CoreStorage logical
    # volume field and never appears for APFS.
    #
    # Two conditions are handled: the progress line has not appeared yet
    # because conversion has not started, and conversion can complete before
    # the line is ever observed, which is what happens when the volume holds
    # little data, since "diskutil apfs encryptVolume" converts the allocated
    # blocks rather than the size of the image. Both phases are bound by a
    # timeout and "line never appeared and FileVault is enabled" is treated as
    # already converted.
    #
    # Note that the output of "diskutil apfs list" is captured and its exit
    # status checked, since a failing query prints nothing and would otherwise
    # be indistinguishable from the progress line having disappeared, which is
    # the condition that means conversion has completed.
    local APFS_LIST_OUTPUT
    local PROGRESS_SEEN=0
    local CONVERT_DEADLINE
    local APPEAR_DEADLINE

    CONVERT_DEADLINE=$(( `date +%s` + 900 ))
    APPEAR_DEADLINE=$(( `date +%s` + 30 ))

    while true
    do
        if ! APFS_LIST_OUTPUT=`diskutil apfs list ${CONTAINER_DEVICE}`
        then
            echo "Unable to determine encryption progress of: ${CONTAINER_DEVICE}."

            exit ${EXIT_FAILURE}
        fi

        if echo "${APFS_LIST_OUTPUT}" | grep -q 'Encryption Progress'
        then
            PROGRESS_SEEN=1

            if test "`date +%s`" -ge ${CONVERT_DEADLINE}
            then
                echo "Encryption did not complete within timeout."

                exit ${EXIT_FAILURE}
            fi
            sleep 5

            continue
        fi

        # The progress line is absent. If it was seen earlier conversion has
        # completed, otherwise conversion has not started yet.
        if test ${PROGRESS_SEEN} -ne 0
        then
            break
        fi

        if test "`date +%s`" -ge ${APPEAR_DEADLINE}
        then
            if echo "${APFS_LIST_OUTPUT}" | grep 'FileVault:' | grep -q 'Yes'
            then
                break
            fi
            echo "Encryption did not start."

            exit ${EXIT_FAILURE}
        fi
        sleep 1
    done

    detach_image "${IMAGE_FILE}.dmg"

    # Note that "detach_image" exits with 0 even when every detach attempt
    # failed, so check that the image is no longer attached. The check below
    # reads the raw image and is only meaningful once the volume has been
    # detached.
    local HDIUTIL_INFO

    if ! HDIUTIL_INFO=`hdiutil info`
    then
        echo "Unable to determine if: ${IMAGE_FILE}.dmg is still attached."

        exit ${EXIT_FAILURE}
    fi

    if echo "${HDIUTIL_INFO}" | grep -F -q "${IMAGE_FILE}.dmg"
    then
        echo "Unable to detach: ${IMAGE_FILE}.dmg."

        exit ${EXIT_FAILURE}
    fi

    # Check that the plaintext canary written before conversion did not survive
    # as cleartext in the raw image.
    #
    # Note that this is a survival check on one known string and not a proof of
    # conversion: its absence does not establish that the volume is fully
    # converted, and its presence need not mean the active volume is
    # unencrypted. It is here to catch a volume that reports "FileVault: Yes"
    # over data that was never converted.
    #
    # Note that the exit status of grep is checked explicitly, since grep exits
    # with 1 if the canary was not found but with a status greater than 1 if
    # the image could not be read, and a read error must not be mistaken for
    # the canary being absent.
    local GREP_EXIT_STATUS=0

    grep -a -q "${CANARY}" "${IMAGE_FILE}.dmg" || GREP_EXIT_STATUS=$?

    if test ${GREP_EXIT_STATUS} -gt 1
    then
        echo "Unable to read: ${IMAGE_FILE}.dmg to check for the plaintext canary."

        exit ${EXIT_FAILURE}
    fi

    if test ${GREP_EXIT_STATUS} -eq 0
    then
        echo "Plaintext canary survived as cleartext in raw image: ${IMAGE_FILE}.dmg."

        exit ${EXIT_FAILURE}
    fi
}

IMAGE_FILE="${SPECIMENS_PATH}/apfs_single_volume_encrypted"

echo "Creating: APFS; with: a single encrypted volume"
create_encrypted_volume "${IMAGE_FILE}" "SingleVolume" "test"

exit ${EXIT_SUCCESS}
