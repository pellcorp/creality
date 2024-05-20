from ubuntu:focal

RUN apt-get update
RUN apt-get install -y python3 build-essential gcc-arm-none-eabi sudo srecord wget

RUN adduser --disabled-password --gecos "" developer && \
  usermod -a -G sudo developer && \
  echo "%sudo ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/nopasswd

RUN mkdir /opt/toolchains && \
    wget https://github.com/ballaswag/k1-discovery/releases/download/1.0.0/mips-gcc720-glibc229.tar.gz -O /tmp/mips-gcc720-glibc229.tar.gz && \
    tar -zxf /tmp/mips-gcc720-glibc229.tar.gz -C /opt/toolchains && \
    rm /tmp/mips-gcc720-glibc229.tar.gz

ENV PATH=/opt/toolchains/mips-gcc720-glibc229/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

USER developer
WORKDIR /home/developer
