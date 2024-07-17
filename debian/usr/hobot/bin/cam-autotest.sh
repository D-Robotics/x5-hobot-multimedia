#!/bin/bash
# See LICENSE for license details.

#####################################
# Common
#####################################

ret=0
ndebug=0

SENSOR_CALLER_PATH="./cam-settings/sensor_caller_list.json"
SENSOR_CALLER_BACKUP_PATH="./cam-settings/.sensor_caller_list.json"
SENSOR_PATH="./cam-settings/sensor_list.json"
SENSOR_BACKUP_PATH="./cam-settings/.sensor_list.json"
#shellcheck disable=SC2046
SCRIPT_WORK_DIR=$(
    cd $(dirname $0)
    pwd
)

info()
{
    echo "$@"
}

debug()
{
    if [ $ndebug -eq 0 ]; then
        echo "$@"
    fi
}

start_service()
{
    ./cam-service -C5,3,5,3 -s4,2,4,2 -i6 -V6 &
    # sleep 10s to make sure the service is ready
    sleep 10 # it needs to wait more time on asic platform
    pid=$(pgrep cam-service)
    if [ "$pid" = "" ]; then
        info "start cam-service failed."
        exit 1
    fi
}

stop_service()
{
    pgrep cam-service | xargs kill
    # sleep 1s for the release of system resources
    sleep 1
}

check_csi_tpg_golden()
{
    # $1 corresponding video index:0, 15, 16, 17
    # $2 resolution: 720, 1080, 2160

    # check video
    if [ "$1" -ne 0 ] && [ "$1" -ne 1 ] && [ "$1" -ne 2 ] && [ "$1" -ne 3 ]; then
        return 0
    fi

    case $2 in
        720) width=1280 golden="926584b9b88611505acbe1de63828583" ;;
        1080) width=1920 golden="3728c01cdf1b6a761c886fb4b4b2ebc4" ;;
        2160) width=3840 golden="fdcc02487a263f23889a49d38dec1cdf" ;;
        *) return 0 ;;
    esac

    md5sum captured_video"$1"_${width}x"$2"_rgb888x* |
        awk -v gd=${golden} -v res="$2" '{                    \
            if($1 == gd)                                    \
                printf("%dp match golden data\n", res);     \
            else                                            \
                printf("%dp %s != %s fail\n", res, $1, gd); \
        }'
}

check_ov5640_tpg_golden()
{
    # $1 corresponding video index:0, 1, ...
    # $2 resolution: 720, 1080
    # $3 format: RAW8, RAW10, YUYV

    # not check video

    raw8_arr=(9ac63adaa54925cbc34aea45e5d80509 5c723bb5d0e2d34480d647df41d51a3f)
    raw10_arr=(4d27dd8b66b08acfabec48d33e8975d0 99f1a9eaba00d11a7b1941e4f7241fd9)
    yuyv_arr=(4d9169d8e5e7b19763218f513471ccb5 18b8a467a8270454467db626a15387f1)
    case $2 in
        720) width=1280 res=0 ;;
        1080) width=1920 res=1 ;;
        *) return 0 ;;
    esac
    case $3 in
        RAW8) golden=${raw8_arr[${res}]} fmt=raw8 ;;
        RAW10) golden=${raw10_arr[${res}]} fmt=raw10 ;;
        YUYV) golden=${yuyv_arr[${res}]} fmt=yuyv ;;
        *) return 0 ;;
    esac

    md5sum captured_video"$1"_${width}x"$2"_${fmt}* |
        awk -v gd="${golden}" -v res="$2" -v fmt=${fmt} ' {              \
            if($1 == gd)                                             \
                printf("%dp %s: match golden data\n", res, fmt);     \
            else                                                     \
                printf("%dp %s: %s != %s fail\n", res, fmt, $1, gd); \
        }'
}

#####################################
# V4L2 Test
#####################################

rm_native_drv()
{
    rmmod vs_sif_nat
    rmmod vs_isp_nat
    rmmod vs_vse_nat
    rmmod hobot_gdc
    rmmod hobot_mipidbg
    rmmod hobot_mipicsi
    rmmod hobot_mipiphy
}

check_and_stop_service()
{
    pid=$(pgrep cam-service)
    if [ "$pid" != "" ]; then
        kill $pid
        sleep 1
    fi
}

init_v4l2()
{
    # reset gdc
    devmem 0x34210094 32 0xa0
    sleep 1
    devmem 0x34210094 32 0

    devmem 0x3418007c 32 0xff5500aa
    devmem 0x31040008 32 0x06001506

    rm_native_drv

    # $1 scene index
    # install module drivers
    modprobe videobuf2_dma_contig
    modprobe v4l2_async
    modprobe vs_cam_ctrl
    modprobe vs_csi_wrapper
    modprobe vs_csi2_snps_v4l
    modprobe vs_sif_v4l
    modprobe vs_isp_v4l
    modprobe vs_vse_v4l scene=$1
    modprobe vs_vid_v4l scene=$1
    modprobe vs_gdc_arm_v4l

    check_and_stop_service
    start_service
}

release_v4l2()
{
    stop_service

    # remove module drivers
    rmmod vs_vid_v4l
    rmmod vs_csi2_snps_v4l
    rmmod vs_csi_wrapper
    rmmod vs_sif_v4l
    rmmod vs_isp_v4l
    rmmod vs_vse_v4l
    rmmod vs_gdc_arm_v4l
    rmmod vs_cam_ctrl
    rmmod videobuf2_dma_contig
    rmmod v4l2_async
}

test_v4l2_case0()
{
    # SENSOR -> CSI -> SIF
    init_v4l2 0
    ./cam-control -e video=0,format=RAW8,width=1280,height=720 -n 5
    check_ov5640_tpg_golden 0 720 RAW8
}

test_v4l2_case1()
{
    # SENSOR -> CSI -> SIF
    init_v4l2 0
    ./cam-control -e video=0,format=RAW10,width=1280,height=720 -n 5
    # TODO: check result
}

test_v4l2_case2()
{
    # SENSOR -> CSI -> SIF
    init_v4l2 0
    ./cam-control -e video=0,format=YUYV,width=1280,height=720 -n 5
    # TODO: check result
}

test_v4l2_case3()
{
    # SENSOR -> CSI -> SIF
    init_v4l2 0
    ./cam-control -e video=0,format=RAW8,width=1920,height=1080 -n 5
    # TODO: check result
}

test_v4l2_case4()
{
    # SENSOR -> CSI -> SIF
    init_v4l2 0
    ./cam-control -e video=0,format=RAW10,width=1920,height=1080 -n 5
    # TODO: check result
}

test_v4l2_case5()
{
    # SENSOR -> CSI -> SIF
    init_v4l2 0
    ./cam-control -e video=0,format=YUYV,width=1920,height=1080 -n 5
    # TODO: check result
}

test_v4l2_case6()
{
    # CSI (TPG x4) -> SIF (x4)

    cp ${SENSOR_PATH} ${SENSOR_BACKUP_PATH}

    echo '{
        "license": "See LICENSE for license details.",
        "sensor-list": [
            {
                "name": "fakess",
                "index" : 0,
                "i2c-bus": -1,
                "mipi": {
                    "lanes": [0, 1, 2, 3],
                    "lane-rate": 200,
                    "vc_id": 0,
                    "csi_tpg": "enable"
                }
            },
            {
                "name": "fakess",
                "index" : 1,
                "i2c-bus": -1,
                "mipi": {
                    "lanes": [0, 1],
                    "lane-rate": 200,
                    "vc_id": 0,
                    "csi_tpg": "enable"
                }
            },
            {
                "name": "fakess",
                "index" : 2,
                "i2c-bus": -1,
                "mipi": {
                    "lanes": [0, 1, 2, 3],
                    "lane-rate": 200,
                    "vc_id": 0,
                    "csi_tpg": "enable"
                }
            },
            {
                "name": "fakess",
                "index" : 3,
                "i2c-bus": -1,
                "mipi": {
                    "lanes": [0, 1],
                    "lane-rate": 200,
                    "vc_id": 0,
                    "csi_tpg": "enable"
                }
            }
        ]
    }' > ${SENSOR_PATH}

    init_v4l2 0

    ./cam-control -e video=0,format=RGB888X,width=1920,height=1080 -n 5
    ./cam-control -e video=1,format=RGB888X,width=1280,height=720 -n 5
    ./cam-control -e video=2,format=RGB888X,width=3840,height=2160 -n 5
    ./cam-control -e video=3,format=RGB888X,width=1280,height=720 -n 5
    # check result
    check_csi_tpg_golden 0 1080
    check_csi_tpg_golden 1 720
    check_csi_tpg_golden 2 2160
    check_csi_tpg_golden 3 720
    mv ${SENSOR_BACKUP_PATH} ${SENSOR_PATH}
}

test_v4l2_case7()
{
    # SENSOR (x4) -> CSI (x4) -> SIF (x4)
    init_v4l2 0
    ./cam-control -e video=0,format=RAW8,width=1280,height=720 \
        -e video=1,format=RAW8,width=1280,height=720 \
        -e video=2,format=RAW8,width=1280,height=720 \
        -e video=3,format=RAW8,width=1280,height=720 \
        -n 5
    # TODO: check result
}

test_v4l2_case8()
{
    # SENSOR -> CSI -> SIF
    init_v4l2 0
    ./cam-control -e video=0,format=NV12,width=1280,height=720 -n 5
    # TODO: check result
}

test_v4l2_case9()
{
    # SENSOR -> CSI -> SIF
    init_v4l2 0
    ./cam-control -e video=0,format=NV12,width=1920,height=1080 -n 5
    # TODO: check result
}

test_ov2778_case()
{
    # test case for ov2778 RAW12 RGB-IR input.
    cp ${SENSOR_PATH} ${SENSOR_BACKUP_PATH}

    sed -i 's/ov5640/ov2778/g' ${SENSOR_PATH}
    sed -i 's/0x3c/0x36/g' ${SENSOR_PATH}

    init_v4l2 0
    ./cam-control -e video=$1,format=RAW12,width=1920,height=1080 -n 5

    mv ${SENSOR_BACKUP_PATH} ${SENSOR_PATH}
}

test_v4l2_case10()
{
    # SENSOR -> CSI -> SIF
    init_v4l2 0
    # option $1 means using which csi port.
    test_ov2778_case 2
}

test_v4l2_case11()
{
    # SENSOR -> CSI -> SIF
    init_v4l2 0
    ./cam-control -e video=3,format=NV12,width=1280,height=720,mode=todisp -n 5
}

test_v4l2_case12()
{
    # SENSOR -> CSI -> SIF -> ISP
    init_v4l2 11
    devmem 0x3d0b0000 32 0xc840
    ./cam-control -e "video=0,format=NV12,width=1280,height=960" -n 16
    # TODO: check result
}

test_v4l2_case13()
{
    # SENSOR (x4) -> CSI (x4) -> SIF (x4) -> ISP
    init_v4l2 11
    devmem 0x3d0b0000 32 0xc840
    ./cam-control -e "video=0,format=NV12,width=1920,height=1080" \
        -e "video=1,format=NV12,width=1920,height=1080" \
        -e "video=2,format=NV12,width=1920,height=1080" \
        -e "video=3,format=NV12,width=1920,height=1080" -n 1
    # TODO: check result
}

test_v4l2_case14()
{
    # SENSOR (x1) -> CSI (x1) -> SIF (x1) -> ISP -> VSE
    # SENSOR (x2) -> CSI (x2) -> SIF (x2) -> ISP
    init_v4l2 9
    devmem 0x3d0b0000 32 0xc840
    ./cam-control -e "video=0,format=NV12,width=720,height=480" \
        -e "video=1,format=NV12,width=240,height=134" \
        -e "video=2,format=NV12,width=112,height=66" \
        -e "video=3,format=NV12,width=1920,height=1080" \
        -e "video=4,format=NV12,width=1920,height=1080" -n 5
    # TODO: check result
}

test_v4l2_case15()
{
    # SENSOR -> CSI -> SIF -> ISP -> GDC -> VSE
    init_v4l2 2
    devmem 0x3d0b0000 32 0xc840
    ./cam-control -e "video=0,format=NV12,width=1920,height=1080" \
        -e "video=1,format=NV12,width=960,height=540" \
        -e "video=2,format=NV12,width=480,height=272" \
        -e "video=3,format=NV12,width=640,height=360" -n 5
    # TODO: check result
}

test_v4l2_case16()
{
    # SENSOR -> CSI -> SIF -> ISP -> VSE
    init_v4l2 6
    devmem 0x3d0b0000 32 0xc840
    ./cam-control -e "video=0,format=NV12,width=720,height=480" \
        -e "video=1,format=NV12,width=360,height=240" \
        -e "video=2,format=NV12,width=720,height=480" -n 5
    # TODO: check result
}

test_v4l2_case17()
{
    # test case for csi-tx -> csi-rx.
    # dc8000 -> csi-tx -> csi-rx/csi-tx(tpg) -> csi-rx(RGB888X).
    cp ${SENSOR_PATH} ${SENSOR_BACKUP_PATH}

    echo '{
        "license": "See LICENSE for license details.",
        "sensor-list": [
            {
                "name": "fakess",
                "index" : 0,
                "i2c-bus": -1,
                "mipi": {
                    "lanes": [0, 1],
                    "lane-rate": 200,
                    "vc_id": 0
                }
            }
        ]
    }' > ${SENSOR_PATH}
    init_v4l2 0
    ./cam-control -e video=0,format=RGB888X,width=1280,height=720 -n 5
    mv ${SENSOR_BACKUP_PATH} ${SENSOR_PATH}
}

test_v4l2_case18()
{
    # test case for csi-tx -> csi-rx.
    # bt1120 -> csi-tx -> csi-rx/csi-rx(YUV422).
    cp ${SENSOR_PATH} ${SENSOR_BACKUP_PATH}

    echo '{
        "license": "See LICENSE for license details.",
        "sensor-list": [
            {
                "name": "fakess",
                "index" : 0,
                "i2c-bus": -1,
                "mipi": {
                    "lanes": [0, 1],
                    "lane-rate": 200,
                    "vc_id": 0
                }
            }
        ]
    }' > ${SENSOR_PATH}
    init_v4l2 0
    ./cam-control -e video=0,format=YUYV,width=1280,height=720 -n 5
    mv ${SENSOR_BACKUP_PATH} ${SENSOR_PATH}
}

test_v4l2_case19()
{
    # SENSOR -> SIF -> VSE
    init_v4l2 12
    ./cam-control -e "video=0,format=NV12,width=3840,height=2160" \
        -e "video=1,format=NV12,width=960,height=540" -n 5
    # TODO: check result
}

test_v4l2_case20()
{
    # SENSOR(x4) -> SIF(x4) -> ISP(x4 insts) -> VSE(x4 insts)
    init_v4l2 13
    devmem 0x3d0b0000 32 0xc840
    ./cam-control -e "video=0,format=NV12,width=1280,height=720" \
        -e "video=1,format=NV12,width=1280,height=720" \
        -e "video=2,format=NV12,width=1280,height=720" \
        -e "video=3,format=NV12,width=1280,height=720" -n 5
    # TODO: check result
}

test_v4l2_case21()
{
    # SENSOR(x1) -> SIF(x1) -> ISP -> VSE
    # SENSOR(x1) -> SIF(x1) -> ISP
    # SENSOR(x1) -> SIF(x1)
    init_v4l2 10
    devmem 0x3d0b0000 32 0xc840
    ./cam-control -e "video=0,format=NV12,width=1280,height=720" \
        -e "video=1,format=NV12,width=1280,height=720" \
        -e "video=2,format=NV12,width=1280,height=720" \
        -e "video=3,format=RAW8,width=1280,height=720" -n 5
    # TODO: check result
}

test_v4l2_case22()
{
    #               CSITX(x1) -> CSIRX(x1) -> SIF(x1) -> DDR
    #                 ^
    #                 | BYPASS
    # SENSOR(x1) -> CSIRX(x1) -> SIF(x1) -> DDR

    cp ${SENSOR_PATH} ${SENSOR_BACKUP_PATH}

    echo '{
        "license": "See LICENSE for license details.",
        "sensor-list": [
            {
                "name": "fakess",
                "index" : 0,
                "i2c-bus": -1,
                "mipi": {
                    "lanes": [0, 1],
                    "lane-rate": 200,
                    "vc_id": 0
                }
            },
            {
                "name": "ov5640",
                "index" : 1,
                "i2c-bus": 2,
                "i2c-addr": "0x3c",
                "tpg": "enable",
                "mipi": {
                    "lanes": [0, 1],
                    "lane-rate": 200,
                    "vc_id": 0,
                    "bypass": 1
                }
            }
        ]
    }' > ${SENSOR_PATH}
    init_v4l2 0
    ./cam-control -e "video=0,format=YUYV,width=1280,height=720" \
        -e "video=1,format=YUYV,width=1280,height=720" -n 5
    # TODO: check result
    mv ${SENSOR_BACKUP_PATH} ${SENSOR_PATH}
}

test_v4l2_case23()
{
    # SENSOR(4lane x1) -> CSIRX(x2) -> SIF(x1) -> DDR

    cp ${SENSOR_PATH} ${SENSOR_BACKUP_PATH}

    echo '{
        "license": "See LICENSE for license details.",
        "sensor-list": [
            {
                "name": "os08a20_4lane",
                "index" : 0,
                "i2c-bus": 1,
                "i2c-addr": "0x36",
                "mipi": {
                    "lanes": [0, 1, 2, 3],
                    "lane-rate": 400,
                    "vc_id": 0
                }
            }
        ]
    }' > ${SENSOR_PATH}
    init_v4l2 0
    ./cam-control -e video=0,format=RAW10,width=1920,height=1080 -n 5
    # TODO: check result
    mv ${SENSOR_BACKUP_PATH} ${SENSOR_PATH}
}

test_v4l2_cases()
{
    if [ "$1" -eq 32767 ] || [ "$1" -eq 0 ]; then
        test_v4l2_case0 "$@"
    fi
    if [ "$1" -eq 32767 ] || [ "$1" -eq 1 ]; then
        test_v4l2_case1 "$@"
    fi
    if [ "$1" -eq 32767 ] || [ "$1" -eq 2 ]; then
        test_v4l2_case2 "$@"
    fi
    if [ "$1" -eq 32767 ] || [ "$1" -eq 3 ]; then
        test_v4l2_case3 "$@"
    fi
    if [ "$1" -eq 32767 ] || [ "$1" -eq 4 ]; then
        test_v4l2_case4 "$@"
    fi
    if [ "$1" -eq 32767 ] || [ "$1" -eq 5 ]; then
        test_v4l2_case5 "$@"
    fi
    if [ "$1" -eq 32767 ] || [ "$1" -eq 6 ]; then
        test_v4l2_case6 "$@"
    fi
    if [ "$1" -eq 32767 ] || [ "$1" -eq 7 ]; then
        test_v4l2_case7 "$@"
    fi
    if [ "$1" -eq 32767 ] || [ "$1" -eq 8 ]; then
        test_v4l2_case8 "$@"
    fi
    if [ "$1" -eq 32767 ] || [ "$1" -eq 9 ]; then
        test_v4l2_case9 "$@"
    fi
    if [ "$1" -eq 32767 ] || [ "$1" -eq 10 ]; then
        test_v4l2_case10 "$@"
    fi
    if [ "$1" -eq 32767 ] || [ "$1" -eq 11 ]; then
        test_v4l2_case11 "$@"
    fi
    if [ "$1" -eq 32767 ] || [ "$1" -eq 12 ]; then
        test_v4l2_case12 "$@"
    fi
    if [ "$1" -eq 32767 ] || [ "$1" -eq 13 ]; then
        test_v4l2_case13 "$@"
    fi
    if [ "$1" -eq 32767 ] || [ "$1" -eq 14 ]; then
        test_v4l2_case14 "$@"
    fi
    if [ "$1" -eq 32767 ] || [ "$1" -eq 15 ]; then
        test_v4l2_case15 "$@"
    fi
    if [ "$1" -eq 32767 ] || [ "$1" -eq 16 ]; then
        test_v4l2_case16 "$@"
    fi
    if [ "$1" -eq 32767 ] || [ "$1" -eq 17 ]; then
        test_v4l2_case17 "$@"
    fi
    if [ "$1" -eq 32767 ] || [ "$1" -eq 18 ]; then
        test_v4l2_case18 "$@"
    fi
    if [ "$1" -eq 32767 ] || [ "$1" -eq 19 ]; then
        test_v4l2_case19 "$@"
    fi
    if [ "$1" -eq 32767 ] || [ "$1" -eq 20 ]; then
        test_v4l2_case20 "$@"
    fi
    if [ "$1" -eq 32767 ] || [ "$1" -eq 21 ]; then
        test_v4l2_case21 "$@"
    fi
    if [ "$1" -eq 32767 ] || [ "$1" -eq 22 ]; then
        test_v4l2_case22 "$@"
    fi
    if [ "$1" -eq 32767 ] || [ "$1" -eq 23 ]; then
        test_v4l2_case23 "$@"
    fi
}

test_v4l2()
{
    debug "test_v4l2 $*"

    case_index=-1
    if [ $# -eq 0 ]; then
        case_index=0
    elif [ "$1" == "all" ]; then
        case_index=32767
    elif [ $# -gt 1 ]; then
        if [ "$2" == "all" ]; then
            case_index=32767
        elif [ "$2" == "0" ]; then
            case_index=0
        elif [ "$2" == "1" ]; then
            case_index=1
        elif [ "$2" == "2" ]; then
            case_index=2
        elif [ "$2" == "3" ]; then
            case_index=3
        elif [ "$2" == "4" ]; then
            case_index=4
        elif [ "$2" == "5" ]; then
            case_index=5
        elif [ "$2" == "6" ]; then
            case_index=6
        elif [ "$2" == "7" ]; then
            case_index=7
        elif [ "$2" == "8" ]; then
            case_index=8
        elif [ "$2" == "9" ]; then
            case_index=9
        elif [ "$2" == "10" ]; then
            case_index=10
        elif [ "$2" == "11" ]; then
            case_index=11
        elif [ "$2" == "12" ]; then
            case_index=12
        elif [ "$2" == "13" ]; then
            case_index=13
        elif [ "$2" == "14" ]; then
            case_index=14
        elif [ "$2" == "15" ]; then
            case_index=15
        elif [ "$2" == "16" ]; then
            case_index=16
        elif [ "$2" == "17" ]; then
            case_index=17
        elif [ "$2" == "18" ]; then
            case_index=18
        elif [ "$2" == "19" ]; then
            case_index=19
        elif [ "$2" == "20" ]; then
            case_index=20
        elif [ "$2" == "21" ]; then
            case_index=21
        elif [ "$2" == "22" ]; then
            case_index=22
        elif [ "$2" == "23" ]; then
            case_index=23
        fi
    fi
    if [ "x$case_index" != "xall" ] && [ $case_index -eq -1 ]; then
        info "invalid input arguments."
        ret=-1
        return
    fi

    test_v4l2_cases $case_index
    release_v4l2
}

#####################################
# NAT Test
#####################################

init_nat()
{
    # install module drivers
    modprobe vs_csi_wrapper
    modprobe vs_csi2_snps_nat
    modprobe vs_sif_nat
    modprobe vs_isp_nat
    modprobe vs_vse_nat

    start_service
}

release_nat()
{
    stop_service

    # remove module drivers
    rmmod vs_csi2_snps_nat
    rmmod vs_csi_wrapper
    rmmod vs_sif_nat
    rmmod vs_isp_nat
    rmmod vs_vse_nat
}

test_nat()
{
    debug "test_nat $*"
    init_nat
    release_nat
}

#####################################
# ISP Unit Test
#####################################

test_isp()
{
    debug "test_isp $*"
    cur_dir=${PWD}
    if [ -d "/mnt/camera/isp_unit_test" ]; then
        echo "working on /mnt/camera/isp_unit_test!"
        cd /mnt/camera/isp_unit_test
    else
        echo "working on ${SCRIPT_WORK_DIR}!"
        cd ${SCRIPT_WORK_DIR}
    fi
    modprobe vs_isp_nat
    isp_test_engine
    sync
    if [ -f "isp_unit_test_verify.sh" ]; then
        ./isp_unit_test_verify.sh
    else
        echo "no verify script found! need manually check result offline!"
    fi
    rmmod vs_isp_nat
    cd ${cur_dir}
}

#####################################
# VSE Unit Test
#####################################

check_vse_golden_all()
{
    pass=0
    fail=0
    if [ -f "out_golden_crc32.txt" ]; then
        while read -r line; do
            filename=$(echo $line | awk '{print $2}')
            golden=$(echo $line | awk '{print $1}')
            result=$(crc32 $filename | awk '{print $1}')
            if [ "$result" = "$golden" ]; then
                pass=$((pass + 1))
                echo "$filename match golden value"
            else
                fail=$((fail + 1))
                echo "$filename fail, expected golden $golden, but $result"
            fi
        done < out_golden_crc32.txt

        echo "pass cases: $pass"
        echo "fail cases: $fail"
    else
        echo "There is no out_golden_crc32.txt"
    fi

}

test_vse()
{
    debug "test_vse $*"
    cur_dir=${PWD}
    if [ -d "/mnt/camera/vse_unit_test" ]; then
        echo "working on /mnt/camera/vse_unit_test!"
        cd /mnt/camera/vse_unit_test
    else
        echo "working on ${SCRIPT_WORK_DIR}/vse_unit_test!"
        cd ${SCRIPT_WORK_DIR}/vse_unit_test
    fi
    modprobe vs_vse_nat
    export ISP_LOG_LEVEL=8
    dw200_test
    check_vse_golden_all

    # rmmod vs_vse_nat
    # rmmod vs_cam_ctrl
    # rmmod hobot_vio_common
    # rmmod hobot_ion_iommu
    # rmmod vs_online_ops
    cd ${cur_dir}
}

check_gdc_golden_all()
{
    pass=0
    fail=0
    if [ -f "out_golden_crc32.txt" ]; then
        while read -r line; do
            filename=$(echo $line | awk '{print $2}')
            golden=$(echo $line | awk '{print $1}')
            result=$(crc32 $filename | awk '{print $1}')
            if [ "$result" = "$golden" ]; then
                pass=$((pass + 1))
                echo "$filename match golden value"
            else
                fail=$((fail + 1))
                echo "$filename fail, expected golden $golden, but $result"
            fi
        done < out_golden_crc32.txt

        echo "pass cases: $pass"
        echo "fail cases: $fail"
    else
        echo "There is no out_golden_crc32.txt"
    fi

}

test_gdc()
{
    debug "test_gdc $*"

    modprobe videobuf2_dma_contig
    modprobe v4l2_async
    modprobe vs_vid_v4l
    modprobe vs_cam_ctrl
    modprobe vs_gdc_arm_v4l
    cur_dir=${PWD}
    if [ -d "/mnt/camera/gdc_unit_test" ]; then
        echo "working on /mnt/camera/gdc_unit_test!"
        cd /mnt/camera/gdc_unit_test
    else
        echo "working on ${SCRIPT_WORK_DIR}/gdc_unit_test!"
        cd ${SCRIPT_WORK_DIR}/gdc_unit_test
    fi
    # reset gdc
    # devmem 0x34210094 32 0x20
    # sleep 1
    # devmem 0x34210094 32 0
    export VSCAM_LOG_LEVEL=0
    gdc-test
    check_gdc_golden_all

    cd ${cur_dir}
    # rmmod vs_vid_v4l
    # rmmod vs_gdc_arm_v4l
    # rmmod vs_cam_ctrl
    # rmmod v4l2_async
    # rmmod videobuf2_dma_contig
}

#####################################
# Main
#####################################

usage()
{
    echo "Usage: $0 [o1 [o2 [...]]]"
    echo "    o1 - all/v4l2/nat/isp/vse/help"
    echo "        all  - run all cases for v4l2 and nat drivers."
    echo "        v4l2 - run cases for v4l2 drivers."
    echo "        nat  - run cases for nat drivers."
    echo "        isp  - run isp unit test cases."
    echo "        vse  - run vse unit test cases."
    echo "        gdc  - run gdc unit test cases."
    echo "        help - show help messages."
    echo "    o2 - all/0/1/2..."
    echo "        all  - run all cases for v4l2 or nat drivers."
    echo "        num  - run a certain case for v4l2 or nat drivers."
    echo "    E.g. $0 all"
    echo "         $0 v4l2 0"
    echo "         $0 nat 1"
    exit 0
}

main()
{
    #shellcheck disable=SC2046
    cd $(dirname "$0") || exit
    if [ $# -gt 0 ] && [ "$1" == "all" ]; then
        test_isp "$@"
        test_vse "$@"
        test_v4l2 "$@"
        test_nat "$@"
        return
    elif [ $# -gt 0 ] && [ "$1" == "isp" ]; then
        test_isp "$@"
        return
    elif [ $# -gt 0 ] && [ "$1" == "vse" ]; then
        test_vse "$@"
        return
    elif [ $# -gt 0 ] && [ "$1" == "gdc" ]; then
        test_gdc "$@"
        return
    elif [ $# -gt 0 ] && [ "$1" == "nat" ]; then
        test_nat "$@"
        return
    elif [ $# -gt 0 ] && [ "$1" == "help" ]; then
        usage "$@"
        return
    else
        test_v4l2 "$@"
        return
    fi
}

main "$@"
info "return of executing $0: $ret"
