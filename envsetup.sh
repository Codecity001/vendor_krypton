#!/bin/bash

# Copyright 2021 AOSP-Krypton Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Clear the screen
clear

# Colors
LR="\033[1;31m"
LG="\033[1;32m"
LP="\033[1;35m"
NC="\033[0m"

# Common tags
ERROR="${LR}Error"
INFO="${LG}Info"
WARN="${LP}Warning"

# Add all officialy supported devices to an array
krypton_products=()
device=""

# Set to non gapps build by default
export GAPPS_BUILD=false

function devices() {
  local tmp="0"
  local LIST="${ANDROID_BUILD_TOP}/vendor/krypton/products/products.list"
  local print=false
  krypton_products=()
  # Check whether to print list of devices
  [ ! -z $1 ] && [ $1 == "-p" ] && print=true && echo -e "${LG}List of officially supported devices and corresponding codes:${NC}"

  while read -r product; do
    if [ ! -z $product ] ; then
      tmp=$(expr $tmp + 1)
      krypton_products+=("$product:$tmp")
      if $print ; then
        echo -ne "${LP}$tmp:${NC} ${LG}$product${NC}\t"
        local pos=$(expr $tmp % 3)
        [ $pos -eq 0 ] && echo -ne "\n"
      fi
    fi
  done < $LIST
  $print && echo ""
}
devices
official=false # Default to unofficial status

function krypton_help() {
cat <<EOF
Krypton specific functions:
- cleanup:    Clean \$OUT directory, logs, as well as intermediate zips if any.
- launch:     Build a full ota.
              Usage: launch <device | codenum> <variant> [-q] [-s] [-g] [-n]
              codenum for your device can be obtained by running devices -p
              -q to run silently.
              -s to generate signed ota.
              -g to build gapps variant.
              -n to not wipe out directory.
- devices:    Usage: devices -p
              Prints all officially supported devices with their code numbers.
- chk_device: Usage: chk_device <device>
              Prints whether or not device is officially supported by KOSP
- dirty:      Run a dirty build.Mandatory to run lunch prior to it's execution.
              Usage: dirty [-q]
              -q to run silently.
- sign:       Sign and build ota.Execute only after a successfull make.
              Usage: sign [-q]
              -q to run silently.
- zipup:      Rename the signed ota with build info.
              Usage: zipup <variant>
- search:     Search in every file in the current directory for a string.Uses xargs for parallel search.
              Usage: search <string>
- reposync:   Sync repo with the following default params: -j\$(nproc --all) --no-clone-bundle --no-tags --current-branch.
              Pass in additional options alongside if any.
- fetchrepos: Set up local_manifest for device and fetch the repos set in vendor/krypton/products/device.deps
              Usage: fetchrepos <device>
- keygen:     Generate keys for signing builds.
              Usage: keygen <dir>
              Default dir is ${ANDROID_BUILD_TOP}/certs
- syncopengapps:  Sync OpenGapps repos.
                  Usage: syncgapps [-i]
                  -i to initialize git lfs in all the source repos
- syncpixelgapps:  Sync our Gapps repo.
                  Usage: syncpixelgapps [-i]
                  -i to initialize git lfs in all the source repos
- merge_aosp: Fetch and merge the given tag from aosp source for the repos forked from aosp in krypton.xml
              Usage: merge_aosp <tag>
              Example: merge_aosp android-11.0.0_r37

If run quietly, full logs will be available in ${ANDROID_BUILD_TOP}/buildlog.
EOF
}

function timer() {
  local time=$(expr $2 - $1)
  local sec=$(expr $time % 60)
  local min=$(expr $time / 60)
  local hr=$(expr $min / 60)
  local min=$(expr $min % 60)
  echo "$hr:$min:$sec"
}

function cleanup() {
  croot
  echo -e "${INFO}: cleaning build directory....${NC}"
  make clean &> /dev/null
  rm -rf *.zip buildlog
  echo -e "${INFO}: done cleaning${NC}"
  return $?
}

function fetchrepos() {
  local deps="${ANDROID_BUILD_TOP}/vendor/krypton/products/${1}.deps"
  local list=() # Array for holding the projects
  local repos=() # Array for storing the values for the <project> tag
  local dir="${ANDROID_BUILD_TOP}/.repo/local_manifests" # Local manifest directory
  local manifest="${dir}/${1}.xml" # Local manifest
  [ -z $1 ] && echo -e "${ERROR}: device name cannot be empty.Usage: fetchrepos <device>${NC}" && return 1
  [ ! -f $deps ] && echo -e "${ERROR}: deps file $deps not found" && return 1 # Return if deps file is not found
  echo -e "${INFO}: Setting up manifest for ${1}${NC}"

  [ ! -d $dir ] && mkdir -p $dir
  echo -e "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<manifest>" > $manifest

  # Grab all the projects
  while read -r project; do
    [[ ! $project =~ ^#.* ]] && list+=("$project")
  done < $deps

  for ((i=0; i<${#list[@]}; i++)); do
    local project=()
    for val in ${list[i]}; do
      project+=($val)
    done
    echo -e "\t<project ${project[@]} />" >> $manifest
  done
  echo "</manifest>" >> $manifest # Manifest has been written
  echo -e "${INFO}: Fetching repos....${NC}"
  reposync # Sync the repos
}

function chk_device() {
  device=""
  official=false
  for entry in ${krypton_products[@]}; do
    local product=${entry%:*}
    local product_num=${entry#*:}
    if [ $1 == $product_num ] || [ $1 == $product ] ; then
      device="$product"
      official=true
      break
    fi
  done
  [ -z $device ] && device="$1"
  # Show official or unofficial status
  if $official ; then
    echo -e "${INFO}: device $device is officially supported by KOSP${NC}"
  else
    echo -e "${WARN}: device $device is not officially supported by KOSP${NC}"
  fi
}

function launch() {
  OPTIND=1
  local variant=""
  local quiet=false
  local sign=false
  local wipe=true
  local GAPPS_BUILD=false

  # Check for official devices
  chk_device $1; shift # Remove device name from options

  # Check for build variant
  check_variant $1
  [ $? -ne 0 ] && echo -e "${ERROR}: invalid build variant${NC}" && return 1
  variant=$1; shift # Remove build variant from options

  while getopts ":qsgn" option; do
    case $option in
      q) quiet=true;;
      s) sign=true;;
      g) GAPPS_BUILD=true;;
      n) wipe=false;;
     \?) echo -e "${ERROR}: invalid option, run hmm and learn the proper syntax${NC}"; return 1
    esac
  done
  export GAPPS_BUILD # Set whether to include gapps in the rom

  # Execute rest of the commands now as all vars are set.
  timeStart=$(date "+%s")
  if $quiet ; then
    $wipe && cleanup
    echo -e "${INFO}: Starting build for $device ${NC}"
    lunch krypton_$device-$variant &>> buildlog
    [ $? -eq 0 ] && dirty -q
    [ $? -eq 0 ] && $sign && sign -q && zipup $variant
    STATUS=$?
  else
    $wipe && rm -rf *.zip buildlog && make clean
    lunch krypton_$device-$variant
    [ $? -eq 0 ] && dirty
    [ $? -eq 0 ] && $sign && sign && zipup $variant
    STATUS=$?
  fi
  endTime=$(date "+%s")
  echo -e "${INFO}: build finished in $(timer $timeStart $endTime)${NC}"

  return $STATUS
}

function dirty() {
  croot
  if [ -z $1 ] ; then
    make -j$(nproc --all) target-files-package otatools && return 0
  elif [ $1 == "-q" ] ; then
    [ -z $KRYPTON_BUILD ] && echo -e "${ERROR}: Target device not found ,have you run lunch?${NC}" && return 1
    echo -e "${INFO}: running make....${NC}"
    local start=$(date "+%s")
    make -j$(nproc --all) target-files-package otatools  &>> buildlog
    [ $? -eq 0 ] && echo -e "\n${INFO}: make finished in $(timer $start $(date "+%s"))${NC}" && return 0
  else
    echo -e "${ERROR}: expected argument \"-q\", provided \"$1\"${NC}" && return 1
  fi
}

function sign() {
  local tfi="$OUT/obj/PACKAGING/target_files_intermediates/*target_files*.zip"
  local apksign="./build/tools/releasetools/sign_target_files_apks -o -d $ANDROID_BUILD_TOP/certs \
                -p out/host/linux-x86 -v $tfi signed-target_files.zip"

  local buildota="./build/tools/releasetools/ota_from_target_files -k $ANDROID_BUILD_TOP/certs/releasekey \
                  -p out/host/linux-x86 -v --block \
                  signed-target_files.zip signed-ota.zip"

  croot
  if [ -z $1 ] ; then
    $apksign && $buildota
  elif [ $1 == "-q" ] ; then
    local start=$(date "+%s")
    if [ -z $KRYPTON_BUILD ] ; then
      echo -e "${ERROR}: target device not found,have you run lunch?${NC}" && return 1
    elif [ ! -f $tfi ] ; then
      echo -e "${ERROR}: target files zip not found,was make successfull?${NC}" && return 1
    fi
    echo -e "${INFO}: signing build......${NC}"
    $apksign &>> buildlog
    [ $? -ne 0 ] && echo -e "${ERROR}: failed to sign build!${NC}" && return 1
    echo -e "${INFO}: done signing build${NC}"
    echo -e "${INFO}: generating ota package.....${NC}"
    $buildota &>> buildlog
    [ $? -ne 0 ] && echo -e "${ERROR}: failed to build ota!${NC}" && return 1
    echo -e "${INFO}: signed ota built from target files package${NC}"
    echo -e "${INFO}: ota generated in $(timer $start $(date "+%s"))${NC}"
    return 0
  else
    echo -e "${ERROR}: expected argument \"-q\", provided \"$1\"${NC}" && return 1
  fi
}

function zipup() {
  croot
  # Version info
  versionMajor=1
  versionMinor=0
  version="v$versionMajor.$versionMinor"
  TAGS=

  # Check build variant and check if ota is present
  check_variant $1
  [ $? -ne 0 ] && echo -e "${ERROR}: must provide a valid build variant${NC}" && return 1
  [ ! -f signed-ota.zip ] && echo -e "${ERROR}: ota not found${NC}" && return 1

  if $official ; then
    TAGS+="-OFFICIAL"
  fi
  if $GAPPS_BUILD; then
    TAGS+="-GAPPS"
  else
    TAGS+="-VANILLA"
  fi

  # Rename the ota with proper build info and timestamp
  SIZE=$(du -b signed-ota.zip | awk '{print $1}')
  NAME="KOSP-${version}-${KRYPTON_BUILD}${TAGS}-$(date "+%Y%m%d")-${1}.zip"
  mv signed-ota.zip $NAME

  TS=$(cat $OUT/system/etc/prop.default | grep "timestamp" | sed 's|ro.krypton.build.timestamp=||')

  echo -e "${INFO}: filesize=${SIZE}"
  echo -e "${INFO}: filename=${NAME}"
  echo -e "${INFO}: timestamp=${TS}"
}

function search() {
  [ -z $1 ] && echo -e "${ERROR}: provide a string to search${NC}" && return 1
  find . -type f -print0 | xargs -0 -P $(nproc --all) grep "$*" && return 0
}

function reposync() {
  local SYNC_ARGS="--no-clone-bundle --no-tags --current-branch"
  repo sync -j$(nproc --all) $SYNC_ARGS $*
  return $?
}

function syncopengapps() {
  local sourceroot="${ANDROID_BUILD_TOP}/vendor/opengapps/sources"
  [ ! -d $sourceroot ] && echo "${ERROR}: OpenGapps repo has not been synced!${NC}" && return 1
  local all="${sourceroot}/all"
  local arm="${sourceroot}/arm"
  local arm64="${sourceroot}/arm64"

  # Initialize git lfs in the repo
  if [ ! -z $1 ] ; then
    if [ $1 == "-i" ] ; then
      for dir in $all $arm $arm64; do
        cd $dir && git lfs install
      done
    fi
  fi

  # Fetch files
  for dir in $all $arm $arm64; do
    cd $dir && git lfs fetch && git lfs checkout
  done
  croot
}

function syncpixelgapps() {
  local sourceroot="${ANDROID_BUILD_TOP}/vendor/google"
  [ ! -d $sourceroot ] && echo "${ERROR}: Gapps repo has not been synced!${NC}" && return 1
  local gms="${sourceroot}/gms"
  local pixel="${sourceroot}/pixel"

  # Initialize git lfs in the repo
  if [ ! -z $1 ] ; then
    if [ $1 == "-i" ] ; then
      for dir in $gms $pixel; do
        cd $dir && git lfs install
      done
    fi
  fi

  # Fetch files
  for dir in $gms $pixel; do
    cd $dir && git lfs fetch && git lfs checkout
  done
  croot
}

function keygen() {
  local certsdir=${ANDROID_BUILD_TOP}/certs
  [ -z $1 ] || certsdir=$1
  rm -rf $certsdir
  mkdir -p $certsdir
  subject=""
  echo "Sample subject: '/C=US/ST=California/L=Mountain View/O=Android/OU=Android/CN=Android/emailAddress=android@android.com'"
  echo "Now enter subject details for your keys:"
  for entry in C ST L O OU CN emailAddress ; do
    echo -n "$entry:"
    read val
    subject+="/$entry=$val"
  done
  for key in releasekey platform shared media networkstack testkey; do
    ./development/tools/make_key $certsdir/$key $subject
  done
}

function merge_aosp() {
  local tag="$1"
  local platformUrl="https://android.googlesource.com/platform/"
  local url=
  croot
  [ -z $tag ] && echo -e "${ERROR}: aosp tag cannot be empty${NC}" && return 1
  local manifest="${ANDROID_BUILD_TOP}/.repo/manifests/krypton.xml"
  if [ -f $manifest ] ; then
    while read line; do
      if [[ $line == *"<project"* ]] ; then
        tmp=$(echo $line | awk '{print $2}' | sed 's|path="||; s|"||')
        if [[ -z $(echo $tmp | grep -iE "krypton|devicesettings") ]] ; then
          cd $tmp
          git -C . rev-parse 2>/dev/null
          if [ $? -eq 0 ] ; then
            if [ $tmp == "build/make" ] ; then
              url="${platformUrl}build"
            else
              url="$platformUrl$tmp"
            fi
            remoteName=$(git remote -v | grep -m 1 "$url" | awk '{print $1}')
            if [ -z $remoteName ] ; then
              echo "adding remote for $tmp"
              remoteName="aosp"
              git remote add $remoteName $url
            fi
            # skip system/core as we have rebased this repo, manually cherry-pick the patches
            if [[ $tmp == "system/core" ]] ; then
              echo -e "${INFO}: skipping $tmp, please do a manual merge${NC}"
              croot
              continue
            fi
            echo -e "${INFO}: merging tag $tag in $tmp${NC}"
            git fetch $remoteName $tag && git merge FETCH_HEAD
            if [ $? -eq 0 ] ; then
              echo -e "${INFO}: merged tag $tag${NC}"
              git push krypton HEAD:A11
              if [ $? -ne 0 ] ; then
                echo -e "${ERROR}: pushing changes failed, please do a manual push${NC}"
              fi
            else
              echo -e "${ERROR}: merging tag $tag failed, please do a manual merge${NC}"
              croot
              return 1
            fi
          else
            echo -e "${ERROR}: $tmp is not a git repo${NC}"
            croot
            return 1
          fi
          croot
        fi
      fi
    done < $manifest
  else
    echo -e "${ERROR}: unable to find $manifest file${NC}" && return 1
  fi
}
