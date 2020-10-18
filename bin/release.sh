#! /usr/bin/env bash
################################################################################
# build.sh                                                                     #
################################################################################
#
# Build Riff docker images
#

################################################################################
# Constants                                                                    #
################################################################################

# Valid rifflearning service build/push targets
RIFF_TARGETS=( riffdata riffrtc riffmm edu-web signalmaster )

# Docker image registry to push/pull built images
IMAGE_REGISTRY=docker.pkg.github.com

# Standard options supplied to all docker build commands
STD_BUILD_OPTS="--rm --force-rm"

################################################################################
# Help                                                                         #
################################################################################
Help()
{
    # Display Help
    echo "Build or push a rifflearning release image"
    echo
    echo "Syntax: $0 [-h] [-t <token>] [-r <git-ref>] <build | push> <riffdata | riffrtc | riffmm | edu-web | signalmaster>"
    echo "options:"
    echo "r     The git reference (tag or branch) of the source to build into an image"
    echo "      or of the image to push. See the * note below for exceptions."
    echo "t     The github token that provides access to the package registry and private"
    echo "      repos. Defaults to GITHUB_TOKEN env var."
    echo "h     Print this Help."
    echo
    echo "*     Some images are based on files in this working directory"
    echo "      - riffmm: use -r to set a version from 'bin/riffmm-versions'. The"
    echo "        image is built using the ./riffmm directory as the docker context"
    echo "      - edu-web: use -r to set the image tag. In general this should be 'latest'."
    echo "        The image is built using the ./edu-web directory as the docker context"
    echo "      - riffrtc: builds and pushes 2 images. Those images are based on an intermediate"
    echo "        prebuild image. The riffrtc-web final image uses the ./pfm-web directory"
    echo "        as its docker context"
    echo
}

################################################################################
# BuildArgOpts                                                                 #
################################################################################
BuildArgOpts()
{
    local ARG_OPTS=
    for arg in ${!BUILD_ARGS[@]}; do
        ARG_OPTS+=" --build-arg ${arg}=${BUILD_ARGS[${arg}]}"
    done

    echo $ARG_OPTS
}

################################################################################
# SetIMAGE                                                                     #
################################################################################
SetIMAGE()
{
    local LOCAL_IMAGE=
    local IMAGE_NAME=

    case $1 in
        riffdata)
            IMAGE_NAME="rifflearning/riff-server/riffdata"
            ;;
        riffrtc-prebuild)
            LOCAL_IMAGE=1
            IMAGE_NAME="rifflearning/rtc-build"
            ;;
        riffrtc-server)
            IMAGE_NAME="rifflearning/riff-docker/riffrtc"
            ;;
        riffrtc-web)
            IMAGE_NAME="rifflearning/riff-docker/pfm-web"
            ;;
        riffmm-server)
            IMAGE_NAME="rifflearning/edu-docker/riffmm"
            ;;
        riffmm-web)
            IMAGE_NAME="rifflearning/edu-docker/edu-web"
            ;;
        signalmaster)
            IMAGE_NAME="rifflearning/signalmaster/signalmaster"
            ;;
    esac

    IMAGE="${IMAGE_NAME}:${TAG}"
    if [ -z "${LOCAL_IMAGE}" ]; then
        IMAGE="${IMAGE_REGISTRY}/${IMAGE}"
    fi
}

################################################################################
# BuildImage                                                                   #
################################################################################
BuildImage()
{
    local CONTEXT=
    local DOCKERFILE=
    local BUILD_STAGE=
    # BUILD_ARGS is an associative array of arg name to its value
    declare -A BUILD_ARGS
    local BUILD_ARGS=()

    SetIMAGE $1
    case $1 in
        riffdata)
            CONTEXT="https://${TOKEN}:@github.com/rifflearning/riff-server.git#${REF}"
            DOCKERFILE="Dockerfile"
            BUILD_ARGS=( [NODE_VER]=12
                         [PORT]=3000
                       )
            ;;
        riffrtc-prebuild)
            CONTEXT="https://${TOKEN}:@github.com/rifflearning/riff-rtc.git#${REF}"
            DOCKERFILE="Dockerfile"
            BUILD_STAGE=build
            BUILD_ARGS=( [NODE_VER]=12
                       )
            ;;
        riffrtc-server)
            CONTEXT="https://${TOKEN}:@github.com/rifflearning/riff-rtc.git#${REF}"
            DOCKERFILE="docker/Dockerfile-prod-server"
            BUILD_ARGS=( [NODE_VER]=12
                         [RTC_BUILD_TAG]=${TAG}
                         [PORT]=3001
                       )
            ;;
        riffrtc-web)
            CONTEXT="./pfm-web"
            DOCKERFILE="./pfm-web/Dockerfile-prod"
            BUILD_ARGS=( [NGINX_VER]=latest
                         [RTC_BUILD_TAG]=${TAG}
                       )
            ;;
        riffmm-server)
            CONTEXT="./riffmm"
            DOCKERFILE="./riffmm/Dockerfile"
            BUILD_STAGE=prod
            source bin/riffmm-versions
            BUILD_ARGS=( [NGINX_VER]=latest
                         [UBUNTU_VER]=latest
                         [NODE_VER]=12
                         [GOLANG_VER]=1.15.3
                         [BUILD_NUMBER]=${TAG}
                         [MM_SERVER_REF]="$(GetRiffMMServerRef ${TAG})"
                         [MM_WEBAPP_REF]="$(GetRiffMMWebRef ${TAG})"
                       )
            ;;
        riffmm-web)
            CONTEXT="./edu-web"
            DOCKERFILE="./edu-web/Dockerfile"
            BUILD_ARGS=( [NGINX_VER]=latest
                       )
            ;;
        signalmaster)
            CONTEXT="https://${TOKEN}:@github.com/rifflearning/signalmaster.git#${REF}"
            DOCKERFILE="Dockerfile"
            ;;
    esac

    echo "Building $1..."

    local BUILD_OPTS="${STD_BUILD_OPTS} $(BuildArgOpts)"
    if [ "${DOCKERFILE}" != "Dockerfile" ]; then
        BUILD_OPTS+=" --file ${DOCKERFILE}"
    fi
    if [ -n "${BUILD_STAGE}" ]; then
        BUILD_OPTS+=" --target ${BUILD_STAGE}"
    fi

    local BUILD_CMD="docker build ${BUILD_OPTS} --tag ${IMAGE} ${CONTEXT}"
    echo ${BUILD_CMD}
    ${BUILD_CMD}
    echo
}

################################################################################
# PushImage                                                                    #
################################################################################
PushImage()
{
    SetIMAGE $1

    echo "Pushing $1..."

    local PUSH_CMD="docker push ${IMAGE}"
    echo ${PUSH_CMD}
    ${PUSH_CMD}
    echo
}

################################################################################
################################################################################
# Process the input options, validate arguments.                               #
################################################################################
# Get the options
QUIET=
REF=
TOKEN=
while getopts ":hqr:t:" option; do
    case $option in
        r) # The git reference to be build (and that determines the image tag)
            REF=${OPTARG}
            ;;
        t) # The github personal access token that provides access to private repos, and pushing/pulling images
            TOKEN=${OPTARG}
            ;;
        h) # display Help
            Help
            exit -1
            ;;
        \?) # incorrect option
            echo "Error: Invalid option"
            exit -1
            ;;
    esac
done

# Remove the getopts processed options
shift $((OPTIND - 1))

# Test validity of and set required arguments
ACTION="$1"
TARGET="$2"
if [ -z "${ACTION}" ] || [ ${ACTION} != "build" -a ${ACTION} != "push" ]; then
    echo "!!! You must specify the action to perform !!!"
    echo
    Help
    exit -1
fi

if [ -z "${TARGET}" ] || [[ ! " ${RIFF_TARGETS[@]} " =~ " ${TARGET} " ]]; then
    echo "!!! You must specify the target riff service to build !!!"
    echo
    Help
    exit -1
fi

if [ -z "${REF}" ]; then
    echo "!!! You must specify the git reference in the repository of the source for the image !!!"
    echo
    Help
    exit -1
fi

# if the token is not specified on the commandline but the GITHUB_TOKEN exists in the environment
# use the GITHUB_TOKEN value
if [ -z "${TOKEN}" ] && [ -n "${GITHUB_TOKEN}" ]; then
    TOKEN="${GITHUB_TOKEN}"
fi

if [ ${ACTION} == "push" ] && ! bin/docker-login-check.sh -q ${IMAGE_REGISTRY}; then
    echo "!!! You do not have valid docker credentials to push to ${IMAGE_REGISTRY}."
    echo "!!! Do a docker login and try again."
    echo
    exit -1
fi

################################################################################
################################################################################
# Main program                                                                 #
################################################################################
################################################################################

TAG=${REF##*/}

if [ "${ACTION}" == "build" ]; then
    # Because riffrtc-server and riffrtc-web depend on the local riffrtc-prebuild
    # we cannot use the --pull option to docker build, so instead we use the Makefile
    # pull-images target to ensure we're using the latest images
    make pull-images

    case ${TARGET} in
        riffdata)
            BuildImage riffdata
            ;;
        riffrtc)
            BuildImage riffrtc-prebuild
            BuildImage riffrtc-server
            BuildImage riffrtc-web
            ;;
        riffmm)
            BuildImage riffmm-server
            ;;
        edu-web)
            BuildImage riffmm-web
            ;;
        signalmaster)
            BuildImage signalmaster
            ;;
        *)
            echo "${TARGET} is not a supported riff service target"
            Help
            exit -1
    esac
elif [ "${ACTION}" == "push" ]; then
    case ${TARGET} in
        riffdata)
            PushImage riffdata
            ;;
        riffrtc)
            PushImage riffrtc-server
            PushImage riffrtc-web
            ;;
        riffmm)
            PushImage riffmm-server
            ;;
        edu-web)
            PushImage riffmm-web
            ;;
        signalmaster)
            PushImage signalmaster
            ;;
        *)
            echo "${TARGET} is not a supported riff service target"
            Help
            exit -1
    esac
fi
