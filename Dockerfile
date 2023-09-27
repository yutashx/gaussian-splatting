# Use the base image with PyTorch and CUDA support
FROM pytorch/pytorch:2.0.1-cuda11.7-cudnn8-devel


# NOTE:
# Building the libraries for this repository requires cuda *DURING BUILD PHASE*, therefore:
# - The default-runtime for container should be set to "nvidia" in the deamon.json file. See this: https://github.com/NVIDIA/nvidia-docker/issues/1033
# - For the above to work, the nvidia-container-runtime should be installed in your host. Tested with version 1.14.0-rc.2
# - Make sure NVIDIA's drivers are updated in the host machine. Tested with 525.125.06

ENV DEBIAN_FRONTEND=noninteractive
ENV QT_XCB_GL_INTEGRATION=xcb_egl
ARG TORCH_CUDA_ARCH_LIST="3.5;5.0;6.0;6.1;7.0;7.5;8.0;8.6+PTX"
ARG COLMAP_GIT_COMMIT=main
ARG CUDA_ARCHITECTURES=75

# Update and install tzdata separately
RUN apt update && apt install -y tzdata

# Install necessary packages
RUN apt install -y git && \
    apt install -y libglew-dev libassimp-dev libboost-all-dev libgtk-3-dev libopencv-dev libglfw3-dev libavdevice-dev libavcodec-dev libeigen3-dev libxxf86vm-dev libembree-dev && \
    apt clean && apt install wget && rm -rf /var/lib/apt/lists/*

# Create a workspace directory and clone the repository
WORKDIR /workspace
RUN git clone https://github.com/graphdeco-inria/gaussian-splatting --recursive

# Create a Conda environment and activate it
WORKDIR /workspace/gaussian-splatting

RUN conda env create --file environment.yml && conda init bash && exec bash && conda activate gaussian_splatting

# Make gaussian_splatting the default environment on start
RUN echo "conda activate gaussian_splatting" >> /root/.bashrc

# Tweak the CMake file for matching the existing OpenCV version. Fix the naming of FindEmbree.cmake
WORKDIR /workspace/gaussian-splatting/SIBR_viewers/cmake/linux
RUN sed -i 's/find_package(OpenCV 4\.5 REQUIRED)/find_package(OpenCV 4.2 REQUIRED)/g' dependencies.cmake
RUN sed -i 's/find_package(embree 3\.0 )/find_package(EMBREE)/g' dependencies.cmake
RUN mv /workspace/gaussian-splatting/SIBR_viewers/cmake/linux/Modules/FindEmbree.cmake /workspace/gaussian-splatting/SIBR_viewers/cmake/linux/Modules/FindEMBREE.cmake

# Fix the naming of the embree library in the rayscaster's cmake
RUN sed -i 's/\bembree\b/embree3/g' /workspace/gaussian-splatting/SIBR_viewers/src/core/raycaster/CMakeLists.txt

# Ready to build the viewer now.
WORKDIR /workspace/gaussian-splatting/SIBR_viewers 
RUN cmake -Bbuild . -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build -j24 --target install

# Install COLMAP
WORKDIR /workspace
RUN git clone https://github.com/colmap/colmap.git
RUN apt-get update && apt-get install -y ninja-build build-essential libboost-program-options-dev libboost-filesystem-dev libboost-graph-dev libboost-system-dev libeigen3-dev libflann-dev libfreeimage-dev libmetis-dev libgoogle-glog-dev libgtest-dev libsqlite3-dev libglew-dev qtbase5-dev libqt5opengl5-dev libcgal-dev libceres-dev imagemagick 
RUN cd colmap && \
    git fetch https://github.com/colmap/colmap.git ${COLMAP_GIT_COMMIT} && \
    git checkout FETCH_HEAD && \
    mkdir build
RUN cd build && \
    cmake .. -GNinja -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCHITECTURES} \\
    colmap/build && \
    ninja && \
    ninja install

WORKDIR /workspace/gaussian-splatting
