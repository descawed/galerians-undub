#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -lt 8 ]]
then
    echo usage: $0 jpsxdec.jar galsdk jp_disc1 jp_disc2 jp_disc3 na_disc1 na_disc2 na_disc3 [--clean] [--force-jp-copy] [--skip-na-copy] [--force-index] [--force-export] [--skip-subs] [--force-patch]
    exit 1
fi

if [[ ! -d ./movies ]]
then
    echo This script must be run from the undub directory.
    exit 1
fi

# commands
jpsxdec_jar=$1
export PYTHONPATH=$2

jp_disc1_in=$3
jp_disc2_in=$4
jp_disc3_in=$5
na_disc1_in=$6
na_disc2_in=$7
na_disc3_in=$8

jpsxdec() {
    java -jar "$jpsxdec_jar" "$@"
}

cdpatch() {
    python3 -m psx.cd "$@"
}

cdb() {
    python3 -m galsdk.db "$@"
}

mxa() {
    python3 -m galsdk.xa mxa "$@"
}

export_videos() {
    jpsxdec -x ./discs/jp_disc$1.bin.idx -a video -dir ./movies/videos -quality high -vf avi:rgb -up Lanczos3
    # move all videos to the root videos directory
    for f in $(find ./movies/videos/T4 -type f -name \*.avi)
    do
        name=$(basename $f | cut -d'.' -f1)
        mv "$f" ./movies/videos/$name.avi
    done
}

rmdir_safe() {
    if [[ -d "$1" ]]
    then
        rmdir "$1"
    fi
}

# options
force_jp_copy=false
skip_na_copy=false
force_index=false
force_export=false
skip_subs=false
force_patch=false

shift 8
while (( "$#" ))
do
    case "$1" in
        --force-jp-copy)
            force_jp_copy=true
            ;;
        --skip-na-copy)
            skip_na_copy=true
            ;;
        --force-index)
            force_index=true
            ;;
        --force-export)
            force_export=true
            ;;
        --force-patch)
            force_patch=true
            ;;
        --clean)
            force_jp_copy=true
            skip_na_copy=false
            force_index=true
            force_export=true
            skip_subs=false
            force_patch=true
            ;;
        --skip-subs)
            skip_subs=true
            ;;
        *)
            echo Unknown option $1
            exit 1
    esac
    shift
done

# copy disc images
echo Copying disc images
if [[ "$force_jp_copy" = true || ! -e ./discs/jp_disc1.bin ]]
then
    cp -f "$jp_disc1_in" ./discs/jp_disc1.bin
fi
if [[ "$force_jp_copy" = true || ! -e ./discs/jp_disc2.bin ]]
then
    cp -f "$jp_disc2_in" ./discs/jp_disc2.bin
fi
if [[ "$force_jp_copy" = true || ! -e ./discs/jp_disc3.bin ]]
then
    cp -f "$jp_disc3_in" ./discs/jp_disc3.bin
fi

# the layout of the NA discs is changed by the undub process, so we default to coyping them to be safe
if [[ "$skip_na_copy" = false || ! -e ./discs/na_disc1.bin ]]
then
    cp -f "$na_disc1_in" ./discs/na_disc1.bin
fi
if [[ "$skip_na_copy" = false || ! -e ./discs/na_disc2.bin ]]
then
    cp -f "$na_disc2_in" ./discs/na_disc2.bin
fi
if [[ "$skip_na_copy" = false || ! -e ./discs/na_disc3.bin ]]
then
    cp -f "$na_disc3_in" ./discs/na_disc3.bin
fi

# create indexes
echo Creating indexes
for f in ./discs/*.bin
do
    index_path=./discs/$(basename "$f").idx
    if [[ "$force_index" = true || ! -e "$index_path" ]]
    then
        jpsxdec -f "$f" -x "$index_path"
    fi
done

# export videos
# jPSXdec doesn't have an option to skip files that already exist, so rather than exhaustively list all files, we'll
# just check for the last one on each disc. if that was exported, that should mean everything else was as well.
echo Exporting videos
if [[ "$force_export" = true || ! -e ./movies/videos/B_M18XA.avi ]]
then
    export_videos 1
fi
if [[ "$force_export" = true || ! -e ./movies/videos/C_M21XA.avi ]]
then
    export_videos 2
fi
if [[ "$force_export" = true || ! -e ./movies/videos/D_M12XA.avi ]]
then
    export_videos 3
fi

# cleanup
rmdir_safe ./movies/videos/T4/MOV
rmdir_safe ./movies/videos/T4/MOV_B
rmdir_safe ./movies/videos/T4/MOV_C
rmdir_safe ./movies/videos/T4/MOV_D
rmdir_safe ./movies/videos/T4

# apply subtitles
if [[ "$skip_subs" = false ]]
then
    echo Applying subtitles

    for f in ./movies/subs/*
    do
        rm -f ./movies/frames/*.png
        video_name=$(basename "$f" | cut -d'-' -f1)
        file_index=$(basename "$f" | cut -d'-' -f2 | cut -d'.' -f1)
        patch_path=./movies/patches/$video_name.xml
        ffmpeg -i ./movies/videos/$video_name.avi -vf subtitles="$f" -vsync 0 ./movies/frames/%04d.png
        if [[ "$force_patch" = true || ! -e "$patch_path" ]]
        then
            echo \<?xml version=\"1.0\"?\> > $patch_path
            echo \<str-replace version=\"0.3\"\> >> $patch_path
            for frame in ./movies/frames/*.png
            do
                # the jPSXdec documentation suggests using partial-replace for things like subtitles to reduce quality loss
                # due to re-encoding. I actually found that I got much worse results with partial-replace, though; the subtitles
                # had frequent bouts of flickering and blurriness. for that reason, we're using replace here.
                frame_index=$(basename "$frame" | cut -d'.' -f1 | bc)
                # jPSXdec uses 0-based indexes but ffmpeg uses 1-based indexes
                echo \<replace frame=\"$(( $frame_index - 1 ))\"\>$frame\</replace\> >> $patch_path
            done
            echo \</str-replace\> >> $patch_path
        fi

        case $(cut -c 1-2 <<< "$video_name") in
            C_)
                disc_num=2
                ;;
            D_)
                disc_num=3
                ;;
            *)
                disc_num=1
                ;;
        esac
        jpsxdec -x ./discs/jp_disc$disc_num.bin.idx -i "$file_index" -replaceframes "$patch_path"
        # TODO: extract raw file and patch into NA disc here
    done

    rm -f ./movies/frames/*.png
fi

echo Done