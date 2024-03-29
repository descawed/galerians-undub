#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -lt 8 ]]
then
    echo usage: $0 JPSXDEC GALSDK JP_DISC1 JP_DISC2 JP_DISC3 NA_DISC1 NA_DISC2 NA_DISC3 [--clean] [--force-jp-copy] [--skip-na-copy] [--force-index] [--force-export] [--skip-subs] [--force-patch] [--skip-fmvs] [--skip-dialogue] [--force-assemble] [--skip-assemble] [--skip-sound] [--skip-delta] [--java java-cmd] [--python python-cmd] [--ffmpeg ffmpeg-cmd] [--xdelta xdelta-cmd] '[--compression djw|fgk|lzma|none]' [--as mips-assembler] [--ld mips-linker]
    echo '    JPSXDEC: path to jpsxdec.jar'
    echo '    GALSDK: path to galsdk root directory'
    echo '    JP_DISC1: path to Japan disc 1 (SLPS-02192)'
    echo '    JP_DISC2: path to Japan disc 2 (SLPS-02193)'
    echo '    JP_DISC3: path to Japan disc 3 (SLPS-02194)'
    echo '    NA_DISC1: path to North America disc 1 (SLUS-00986)'
    echo '    NA_DISC2: path to North America disc 2 (SLUS-01098)'
    echo '    NA_DISC3: path to North America disc 3 (SLUS-01099)'
    echo '    --clean: enable all --force options (except --force-assemble) and disable all --skip options'
    echo '    --force-jp-copy: copy Japan discs even if they already exist'
    echo "    --skip-na-copy: don't copy North America discs (this is normally always done because the undub process alters these files)"
    echo '    --force-index: recreate jPSXdec indexes even if they already exist'
    echo "    --force-export: export FMVs from the Japan discs even if they've already been exported"
    echo "    --skip-subs: don't burn subtitles into exported FMVs"
    echo '    --force-patch: recreate jPSXdec subtitle patch files even if they already exist'
    echo "    --skip-fmvs: don't copy FMVs to North America discs"
    echo "    --skip-dialogue: don't copy non-FMV spoken dialogue to North America discs or apply relevant patches"
    echo '    --force-assemble: assemble code patches even if binaries already exist and are newer'
    echo "    --skip-assemble: as long as binaries exist, don't assemble code patches even if the source files are newer"
    echo "    --skip-sound: don't copy non-cutscene speech and sound effects to North America discs"
    echo "    --skip-delta: don't create xdelta patches of the changes applied"
    echo '    --java: Java command name/path to run jPSXdec with (default: java)'
    echo '    --python: Python command name/path to run galsdk with (default: python3)'
    echo '    --ffmpeg: ffmpeg command name/path for FMV subtitle process (default: ffmpeg)'
    echo '    --xdelta: xdelta command name/path for creating final patches (default: xdelta3)'
    echo '    --compression: compression algorithm to use with xdelta (default: lzma)'
    echo '    --as: assembler to use for assembling code patches (default: mips-linux-gnu-as)'
    echo '    --ld: linker to use for creating patch binaries (default: mips-linxu-gnu-ld)'
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
    "$java" -jar "$jpsxdec_jar" "$@"
}

cdpatch() {
    "$python" -m psx.cd patch "$@"
}

exepatch() {
    "$python" -m psx.exe "$@"
}

cdextract() {
    "$python" -m psx.cd extract "$@"
}

cdb() {
    "$python" -m galsdk.db "$@"
}

sdb() {
    "$python" -m galsdk.string "$@"
}

mxa() {
    "$python" -m galsdk.xa mxa "$@"
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

build_patches() {
    for f in ./exe/src/*.$1.s
    do
        address=$(basename "$f" | cut -d'.' -f1)
        object_path="./exe/bin/$address.$1.o"
        bin_path="./exe/bin/$address.$1.bin"
        if [[ ! -e "$bin_path" || "$f" -nt "$bin_path" || "$force_assemble" = true ]]
        then
            "$as" -o "$object_path" --no-pad-sections -EL -mips1 -mno-pdr "$f"
            echo "SECTIONS { . = 0x$address; .text . : SUBALIGN(0) { *(.text) } /DISCARD/ : { *(*) } }" > ./exe/src/linker.ld
            "$ld" -s -e "0x$address" --oformat binary -o "$bin_path" -T ./exe/src/linker.ld "$object_path"
        fi
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
skip_fmvs=false
force_patch=false
force_assemble=false
skip_assemble=false
skip_dialogue=false
skip_sound=false
skip_delta=false

# commands
java=java
python=python3
ffmpeg=ffmpeg
xdelta=xdelta3
compression=lzma
# tools come from binutils-mips-linux-gnu
as=mips-linux-gnu-as
ld=mips-linux-gnu-ld

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
            skip_fmvs=false
            force_patch=true
            # force_assemble is intentionally omitted because the binaries should be packaged with the repo
            skip_assemble=false
            skip_dialogue=false
            skip_sound=false
            skip_delta=false
            ;;
        --skip-subs)
            skip_subs=true
            ;;
        --skip-fmvs)
            skip_fmvs=true
            ;;
        --force-assemble)
            force_assemble=true
            ;;
        --skip-assemble)
            skip_assemble=true
            ;;
        --skip-dialogue)
            skip_dialogue=true
            ;;
        --skip-sound)
            skip_sound=true
            ;;
        --skip-delta)
            skip_delta=true
            ;;
        --java)
            shift
            java=$1
            ;;
        --python)
            shift
            python=$1
            ;;
        --ffmpeg)
            shift
            ffmpeg=$1
            ;;
        --xdelta)
            shift
            xdelta=$1
            ;;
        --compression)
            shift
            compression=$1
            ;;
        --as)
            shift
            as=$1
            ;;
        --ld)
            shift
            ld=$1
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
    echo -n "Copying JP disc 1... "
    cp -f "$jp_disc1_in" ./discs/jp_disc1.bin
    echo done
else
    echo JP disc 1 already exists
fi
if [[ "$force_jp_copy" = true || ! -e ./discs/jp_disc2.bin ]]
then
    echo -n "Copying JP disc 2... "
    cp -f "$jp_disc2_in" ./discs/jp_disc2.bin
    echo done
else
    echo JP disc 2 already exists
fi
if [[ "$force_jp_copy" = true || ! -e ./discs/jp_disc3.bin ]]
then
    echo -n "Copying JP disc 3... "
    cp -f "$jp_disc3_in" ./discs/jp_disc3.bin
    echo done
else
    echo JP disc 3 already exists
fi

# the layout of the NA discs is changed by the undub process, so we default to coyping them to be safe
if [[ "$skip_na_copy" = false || ! -e ./discs/na_disc1.bin ]]
then
    echo -n "Copying NA disc 1... "
    cp -f "$na_disc1_in" ./discs/na_disc1.bin
    echo done
else
    echo Skipping NA disc 1 copy
fi
if [[ "$skip_na_copy" = false || ! -e ./discs/na_disc2.bin ]]
then
    echo -n "Copying NA disc 2... "
    cp -f "$na_disc2_in" ./discs/na_disc2.bin
    echo done
else
    echo Skipping NA disc 2 copy
fi
if [[ "$skip_na_copy" = false || ! -e ./discs/na_disc3.bin ]]
then
    echo -n "Copying NA disc 3... "
    cp -f "$na_disc3_in" ./discs/na_disc3.bin
    echo done
else
    echo Skipping NA disc 3 copy
fi

# create indexes
header Creating indexes
for f in ./discs/*.bin
do
    index_path=./discs/$(basename "$f").idx
    if [[ "$force_index" = true || ! -e "$index_path" ]]
    then
        jpsxdec -f "$f" -x "$index_path"
    else
        echo $index_path already exists
    fi
done

# export videos
# jPSXdec doesn't have an option to skip files that already exist, so rather than exhaustively list all files, we'll
# just check for the last one on each disc. if that was exported, that should mean everything else was as well.
header Exporting videos
if [[ "$force_export" = true || ! -e ./movies/videos/B_M18XA.avi ]]
then
    export_videos 1
else
    echo Disc 1 videos already exported
fi
if [[ "$force_export" = true || ! -e ./movies/videos/C_M21XA.avi ]]
then
    export_videos 2
else
    echo Disc 2 videos already exported
fi
if [[ "$force_export" = true || ! -e ./movies/videos/D_M12XA.avi ]]
then
    export_videos 3
else
    echo Disc 3 videos already exported
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
        "$ffmpeg" -i ./movies/videos/$video_name.avi -vf subtitles="$f" -fps_mode passthrough ./movies/frames/%d.png
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
                # ffmpeg can't edit files in place, so output to a temp image then replace the original
                "$ffmpeg" -y -i "$jp_path" -i ./movies/title_frames/$(( na_frame++ )).png -filter_complex "[1]crop=$w:$h:$x:$y[t];[0][t]overlay=$x:$y" -update 1 ./movies/frames/tmp.png
                mv -f ./movies/frames/tmp.png "$jp_path"
                ((num_frames--))
            done
        fi

        jpsxdec -x ./discs/jp_disc$disc_num.bin.idx -i "$file_index" -replaceframes "$patch_path"
        # now that the video stream has been patched, extract the raw file
        jpsxdec -x ./discs/jp_disc$disc_num.bin.idx -i $(( file_index - 1 )) -dir ./movies/raw -raw
    done

    # move videos up from subdirectories
    for f in $(find ./movies/raw/T4 -type f -name \*.STR)
    do
        name=$(basename $f | cut -d'.' -f1)
        mv "$f" ./movies/raw/$name.STR
    done

    # cleanup
    rm -f ./movies/frames/*.png
    rm -f ./movies/title_frames/*.png
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

# patch raw videos into the NA discs
if [[ "$skip_fmvs" = false ]]
then
    header Patching FMVs

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

        echo -n "Patching $video_name... "
        cdpatch -r ./discs/na_disc$disc_num.bin "\\T4\\MOV$suffix\\$video_name;1" "$f"
        echo done
    done
fi

# dialogue outside of FMVs
if [[ "$skip_dialogue" = false ]]
then
    header Patching dialogue

    build_patches shared
    for disc_num in {1..3}
    do
        case "$disc_num" in
            1)
                jp_exe_name=SLPS_021.92
                na_exe_name=SLUS_009.86
                ;;
            2)
                jp_exe_name=SLPS_021.93
                na_exe_name=SLUS_010.98
                ;;
            3)
                jp_exe_name=SLPS_021.94
                na_exe_name=SLUS_010.99
                ;;
        esac

        rm -f ./voice/extract/SL*
        rm -f ./voice/extract/*.BIN
        rm -f ./voice/extract/DISPLAY.CDB
        rm -f ./voice/extract/strings.txt
        rm -f ./voice/mxa/XA.MXA
        rm -f ./voice/mxa/*.XDB
        rm -f ./voice/display/0*
        echo -n "Extracting from disc $disc_num... "
        cdextract ./discs/na_disc$disc_num.bin ./voice/extract "\\$na_exe_name;1" '\T4\DISPLAY.CDB;1'
        cdextract ./discs/jp_disc$disc_num.bin ./voice/extract "\\T4\\$jp_exe_name;1"
        cdextract -r ./discs/jp_disc$disc_num.bin ./voice/extract '\T4\XA'
        echo done

        # patch the exe to display subtitles for XA audio
        echo -n "Patching EXE... "
        build_patches $disc_num
        for f in ./exe/bin/*.shared.bin ./exe/bin/*.$disc_num.bin
        do
            address=$(basename "$f" | cut -d'.' -f1)
            exepatch "./voice/extract/$na_exe_name" "$address" "$f"
        done
        cdpatch ./discs/na_disc$disc_num.bin "\\$na_exe_name;1" "./voice/extract/$na_exe_name"
        echo done

        # export Japanese dialogue to Western format
        echo -n "Patching audio... "
        cdb unpack ./voice/extract/DISPLAY.CDB ./voice/display
        mxa -m "./voice/mxa/$disc_num.json" "./voice/extract/$jp_exe_name" "$disc_num" ./voice/mxa $(find ./voice/extract -name \*.BIN | sort)
        xdb_name=$(printf '%03d' $(( disc_num - 1 )))
        mv -f "./voice/mxa/$xdb_name.XDB" "./voice/display/$xdb_name"
        cdpatch -r ./discs/na_disc$disc_num.bin '\T4\XA.MXA;1' ./voice/mxa/XA.MXA
        echo done

        # add subtitle messages
        echo -n "Patching messages... "
        for f in ./voice/subs/*.txt
        do
            index=$(basename "$f" | cut -d'.' -f1)
            sdb unpack "./voice/display/$index" ./voice/extract/strings.txt
            cat "$f" >> ./voice/extract/strings.txt
            sdb pack ./voice/extract/strings.txt "./voice/display/$index"
        done
        cdb pack ./voice/extract/DISPLAY.CDB $(find ./voice/display -name 0\* | sort)
        cdpatch ./discs/na_disc$disc_num.bin '\T4\DISPLAY.CDB;1' ./voice/extract/DISPLAY.CDB
        echo done
    done

    # cleanup
    rm -f ./exe/bin/*.o
    rm -f ./exe/src/*.ld
    rm -f ./voice/extract/SL*
    rm -f ./voice/extract/*.BIN
    rm -f ./voice/extract/DISPLAY.CDB
    rm -f ./voice/extract/strings.txt
    rm -f ./voice/mxa/XA.MXA
    rm -f ./voice/mxa/*.XDB
    rm -f ./voice/display/0*
fi

# NPC barks like "Rion!" and "This way!"
if [[ "$skip_sound" = false ]]
then
    header Patching sound

    for disc_num in {1..3}
    do
        echo -n "Patching disc $disc_num sound... "
        rm -f ./sound/SOUND.CDB
        cdextract ./discs/jp_disc$disc_num.bin ./sound '\T4\SOUND.CDB;1'
        cdpatch ./discs/na_disc$disc_num.bin '\T4\SOUND.CDB;1' ./sound/SOUND.CDB
        echo done
    done

    rm -f ./sound/SOUND.CDB
fi

if [[ "$skip_delta" = false ]]
then
    header Creating patches

    rm -f ./output/*.xdelta

    echo -n "Creating patch for disc 1... "
    "$xdelta" -S "$compression" -s "$na_disc1_in" ./discs/na_disc1.bin ./output/disc1.xdelta
    echo done

    echo -n "Creating patch for disc 2... "
    "$xdelta" -S "$compression" -s "$na_disc2_in" ./discs/na_disc2.bin ./output/disc2.xdelta
    echo done

    echo -n "Creating patch for disc 3... "
    "$xdelta" -S "$compression" -s "$na_disc3_in" ./discs/na_disc3.bin ./output/disc3.xdelta
    echo done
fi

echo
echo Undub process complete. Patches can be found in the output folder.