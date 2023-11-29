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

header() {
    echo
    echo '########################################'
    printf '# %-36s #\n' "$*"
    echo '########################################'
    echo
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
header Copying disc images
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
header Creating indexes
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
header Exporting videos
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
    header Applying subtitles

    rm -f ./movies/raw/*.STR
    for f in ./movies/subs/*
    do
        rm -f ./movies/frames/*.png
        video_name=$(basename "$f" | cut -d'-' -f1)
        file_index=$(basename "$f" | cut -d'-' -f2 | cut -d'.' -f1)
        patch_path=./movies/patches/$video_name.xml
        ffmpeg -i ./movies/videos/$video_name.avi -vf subtitles="$f" -fps_mode passthrough ./movies/frames/%d.png
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

        # for the stage A and stage D intro videos, we need to patch in the English title text
        if [[ "$video_name" = M02XA || "$video_name" = D_M01XA ]]
        then
            rm -f ./movies/title_frames/*.png

            # it's important that the x and y coordinates be even because ffmpeg's overlay filter seems to have a limitation
            # where it can only overlay at even coordinates, so odd coordinates will result in the overlaid image being offset
            # by 1 pixel.
            if [[ "$video_name" = M02XA ]]
            then
                jp_frame=449
                na_frame=443
                na_index=1911
                num_frames=112
                x=34
                y=68
                w=250
                h=39
            else
                jp_frame=548
                na_frame=546
                na_index=1911
                num_frames=111
                x=90
                y=68
                w=139
                h=38
            fi

            # extract frames from the English version
            jpsxdec -x ./discs/na_disc$disc_num.bin.idx -i "$na_index" -dir ./movies/title_frames -quality high -vf png -up Lanczos3
            # move all frames to the root directory
            for f in $(find ./movies/title_frames/T4 -type f -name \*.png)
            do
                name=$(basename $f | cut -d'[' -f3 | cut -d']' -f1 | bc)
                mv "$f" ./movies/title_frames/$name.png
            done

            # patch English title text into Japanese frame
            while (( "$num_frames" ))
            do
                # pre-increment jp_frame because ffmpeg uses 1-based indexes
                jp_path=./movies/frames/$(( ++jp_frame )).png
                # ffmpeg can't edit files in place, so output to a temp image, remove the original, then rename the temp
                ffmpeg -y -i "$jp_path" -i ./movies/title_frames/$(( na_frame++ )).png -filter_complex "[1]crop=$w:$h:$x:$y[t];[0][t]overlay=$x:$y" -update 1 ./movies/frames/tmp.png
                rm -f "$jp_path"
                mv ./movies/frames/tmp.png "$jp_path"
                ((num_frames--))
            done
        fi

        jpsxdec -x ./discs/jp_disc$disc_num.bin.idx -i "$file_index" -replaceframes "$patch_path"
        # now that the video stream has been patched, extract the raw file
        jpsxdec -x ./discs/jp_disc$disc_num.bin.idx -i $(( file_index - 1 )) -dir ./movies/raw -raw
    done

    # patch raw videos into the NA discs
    header Patching NA FMVs

    for f in $(find ./movies/raw/T4 -type f -name \*.STR)
    do
        name=$(basename $f | cut -d'.' -f1)
        mv "$f" ./movies/raw/$name.STR
    done

    for f in ./movies/raw/*.STR
    do
        video_name=$(basename "$f")
        case $(cut -c 1-2 <<< "$video_name") in
            C_)
                disc_num=2
                suffix=_C
                ;;
            D_)
                disc_num=3
                suffix=_D
                ;;
            B_)
                disc_num=1
                suffix=_B
                ;;
            *)
                disc_num=1
                suffix=''
                ;;
        esac

        cdpatch -r ./discs/na_disc$disc_num.bin "\T4\MOV$suffix\\$video_name;1" "$f"
    done

    # cleanup
    rm -f ./movies/frames/*.png
    rm -f ./movies/title_frames/*.png
    rm -f ./movies/raw/*.STR
    rmdir_safe ./movies/frames/T4/MOV
    rmdir_safe ./movies/frames/T4/MOV_B
    rmdir_safe ./movies/frames/T4/MOV_C
    rmdir_safe ./movies/frames/T4/MOV_D
    rmdir_safe ./movies/frames/T4
    rmdir_safe ./movies/title_frames/T4/MOV
    rmdir_safe ./movies/title_frames/T4/MOV_B
    rmdir_safe ./movies/title_frames/T4/MOV_C
    rmdir_safe ./movies/title_frames/T4/MOV_D
    rmdir_safe ./movies/title_frames/T4
    rmdir_safe ./movies/raw/T4/MOV
    rmdir_safe ./movies/raw/T4/MOV_B
    rmdir_safe ./movies/raw/T4/MOV_C
    rmdir_safe ./movies/raw/T4/MOV_D
    rmdir_safe ./movies/raw/T4
fi

echo Done