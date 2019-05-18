# Based on cuteradio docker script by:
# Copyright 2019, Burkhard Stubert (DBA Embedded Use)
# Copyright 2019, Alexander Filyanov

# In any directory on the docker host, perform the following actions:
#   * Copy this Dockerfile in the directory.
#   * Create input and output directories: mkdir -p yocto/output yocto/input
#   * Build the Docker image with the following command:
#     docker build --no-cache --build-arg "host_uid=$(id -u)" --build-arg "host_gid=$(id -g)" \
#         --tag "marsboard:latest" .
#   * Run the Docker image, which in turn runs the Yocto and which produces the Linux rootfs,
#     with the following command:
#     docker run -it --rm -v $PWD/yocto/output:/home/yocto/output marsboard:latest

# Use Ubuntu 18.04 LTS as the basis for the Docker image.
FROM ubuntu:18.04

# Install all the Linux packages required for Yocto builds. Note that the packages python3,
# tar, locales and cpio are not listed in the official Yocto documentation. The build, however,
# without them.
RUN apt-get update && apt-get -y install gawk wget git-core diffstat unzip texinfo gcc-multilib \
     build-essential chrpath socat cpio python python3 python3-pip python3-pexpect \
     xz-utils debianutils iputils-ping libsdl1.2-dev xterm tar locales curl repo mc

# By default, Ubuntu uses dash as an alias for sh. Dash does not support the source command
# needed for setting up the build environment in CMD. Use bash as an alias for sh.
RUN rm /bin/sh && ln -s bash /bin/sh

# Set the locale to en_US.UTF-8, because the Yocto build fails without any locale set.
RUN locale-gen en_US.UTF-8 && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LC_ALL en_US.UTF-8

ENV USER_NAME marsboard
ENV PROJECT marsboard
ENV PROJECT_IMAGE image-multimedia-full
ENV BRANCH thud

# The running container writes all the build artefacts to a host directory (outside the container).
# The container can only write files to host directories, if it uses the same user ID and
# group ID owning the host directories. The host_uid and group_uid are passed to the docker build
# command with the --build-arg option. By default, they are both 1001. The docker image creates
# a group with host_gid and a user with host_uid and adds the user to the group. The symbolic
# name of the group and user is marsboard.
ARG host_uid=1001
ARG host_gid=1001
RUN groupadd -g $host_gid $USER_NAME && useradd -g $host_gid -m -s /bin/bash -u $host_uid $USER_NAME

# Perform the Yocto build as user cuteradio (not as root).
# NOTE: The USER command does not set the environment variable HOME.

# By default, docker runs as root. However, Yocto builds should not be run as root, but as a 
# normal user. Hence, we switch to the newly created user marsboard.
USER $USER_NAME

# Create the directory structure for the Yocto build in the container. The lowest two directory
# levels must be the same as on the host.
ARG BUILD_INPUT_DIR=/home/$USER_NAME/yocto/input
ARG BUILD_CONF_DIR=$BUILD_INPUT_DIR/build/conf
ARG BUILD_SOURCES_DIR=$BUILD_INPUT_DIR/sources
ARG BUILD_OUTPUT_DIR=/home/$USER_NAME/yocto/output
RUN mkdir -p $BUILD_INPUT_DIR $BUILD_SOURCES_DIR $BUILD_CONF_DIR $BUILD_OUTPUT_DIR
ENV BUILD_SOURCES_DIR $BUILD_SOURCES_DIR
ENV BUILD_CONF_DIR $BUILD_CONF_DIR
ENV BUILD_INPUT_DIR $BUILD_INPUT_DIR
ENV BUILD_OUTPUT_DIR $BUILD_OUTPUT_DIR

# Initiate the Freescale repo script to prepare build environment for selected branch.
WORKDIR $BUILD_INPUT_DIR
RUN repo init -u https://github.com/Freescale/fsl-community-bsp-platform -b $BRANCH
RUN repo sync

# Patch a necessary project files
WORKDIR $BUILD_SOURCES_DIR
RUN git clone https://github.com/PheeL79/meta-marsboard-bsp.git -b $BRANCH
RUN patch ./poky/documentation/ref-manual/ref-qa-checks.xml \
	./meta-marsboard-bsp/poky/documentation/ref-manual/0001-package-name-valid-chars.patch
RUN patch ./poky/meta/lib/oe/utils.py \
	./meta-marsboard-bsp/poky/meta/lib/oe/0001-subprocess-output.patch
RUN patch ./poky/meta/classes/buildhistory.bbclass \
	./meta-marsboard-bsp/poky/meta/classes/0002-package-name-valid-chars.patch
RUN patch ./poky/meta/classes/insane.bbclass \
	./meta-marsboard-bsp/poky/meta/classes/0003-package-name-valid-chars.patch

# Prepare Yocto's build environment. If TEMPLATECONF is set, the script oe-init-build-env will
# install the customised files bblayers.conf and local.conf. This script initialises the Yocto
# build environment. The bitbake command builds the rootfs for our embedded device.
WORKDIR $BUILD_INPUT_DIR
ENV TEMPLATECONF $BUILD_SOURCES_DIR/meta-marsboard-bsp/build/conf
RUN cp $TEMPLATECONF/* $BUILD_CONF_DIR/
CMD MACHINE=marsboard DISTRO=fslc-framebuffer source $BUILD_INPUT_DIR/setup-environment build \
	&& bitbake $PROJECT_IMAGE
