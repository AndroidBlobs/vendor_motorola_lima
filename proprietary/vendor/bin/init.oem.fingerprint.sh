#!/vendor/bin/sh
#
# Identify fingerprint sensor model
#
# Copyright (c) 2019 Lenovo
# All rights reserved.
#

script_name=${0##*/}
script_name=${script_name%.*}
function log {
    echo "$script_name: $*" > /dev/kmsg
}

utag_name_fps_id=fps_id
utag_fps_id=/proc/hw/$utag_name_fps_id

utag_name_fps_id2=fps_id2
utag_fps_id2=/proc/hw/$utag_name_fps_id2

FPS_VENDOR_NONE=none
FPS_VENDOR_FPC=fpc
FPS_VENDOR_GOODIX=goodix

function ident_fps {
    log "- identify FPC sensor"
    /vendor/bin/hw/fpc_ident
    if [ $? == 0 ]; then
        log "FPC detected"
        echo $FPS_VENDOR_FPC
    else
        log "FPC failed"
        echo $FPS_VENDOR_GOODIX
    fi
}

utag_reload=/proc/hw/reload

status=$(cat $utag_reload)
if [ $status == 2 ]; then
    log "start to reload utag procfs ..."
    echo "1" > $utag_reload
    status=$(cat $utag_reload)
    while [ $status == 1 ]; do
        sleep 1
        status=$(cat $utag_reload)
    done
    log "finish"
fi

utag_new=/proc/hw/all/new

if [ ! -d $utag_fps_id ]; then
    log "- create utag: $utag_name_fps_id"
    echo $utag_name_fps_id > $utag_new
fi

if [ ! -d $utag_fps_id2 ]; then
    log "- create utag: $utag_name_fps_id2"
    echo $utag_name_fps_id2 > $utag_new
fi

prop_fps_id=persist.vendor.hardware.fingerprint
prop_vendor=$(getprop $prop_fps_id)
if [ -z $prop_vendor ]; then
    prop_vendor=none
fi
log "prop_vendor: $prop_vendor"

fps_vendor=$(cat $utag_fps_id/ascii)
log "FPS vendor: $fps_vendor"
fps_vendor2=$(cat $utag_fps_id2/ascii)
log "FPS vendor (last): $fps_vendor2"

if [ -z $fps_vendor ]; then
    log "FPS vendor: null???"
    fps_vendor=$FPS_VENDOR_NONE
fi

fps_vendor_current=$fps_vendor

if [ $fps_vendor == $FPS_VENDOR_NONE ]; then
    fps_ident_vendor=$(ident_fps)
#    echo $fps_ident_vendor > $utag_fps_id/ascii
    fps_vendor_current=$fps_ident_vendor
fi


prop_fps_status=vendor.hw.fingerprint.status

FPS_STATUS_NONE=none
FPS_STATUS_OK=ok

setprop $prop_fps_status $FPS_STATUS_NONE
if [ $fps_vendor_current == $FPS_VENDOR_FPC ]; then
    log "start fps_hal"
    start fps_hal
else
    log "start goodix_hal"
    start vendor.fps_hal
fi

log "wait for HAL finish ..."
fps_status=$(getprop $prop_fps_status)
while [ $fps_status == $FPS_STATUS_NONE ]; do
    sleep 1
    fps_status=$(getprop $prop_fps_status)
done
log "fingerprint HAL status: $fps_status"

if [ $fps_status == $FPS_STATUS_OK ]; then
    log "HAL success"
    if [ $prop_vendor != $fps_vendor_current ]; then
        log "rewrite prop_vendor: $fps_vendor_current"
        setprop $prop_fps_id $fps_vendor_current
    fi

    if [ $fps_vendor == $fps_vendor_current ]; then
        return 0
    fi
    log "- update FPS vendor"
    if [ $fps_vendor != $FPS_VENDOR_NONE ]; then
        echo $fps_vendor > $utag_fps_id2/ascii
    fi
    echo $fps_vendor_current > $utag_fps_id/ascii
    log "- done"
    return 0
fi

log "error: HAL fail"
if [ $fps_vendor != $FPS_VENDOR_NONE ]; then
    echo $fps_vendor > $utag_fps_id2/ascii
    echo $FPS_VENDOR_NONE > $utag_fps_id/ascii
fi
if [ $prop_vendor != $FPS_VENDOR_NONE ]; then
    log "rewrite prop_vendor: $FPS_VENDOR_NONE"
    setprop $prop_fps_id $FPS_VENDOR_NONE
fi

log "- done"
return 1
