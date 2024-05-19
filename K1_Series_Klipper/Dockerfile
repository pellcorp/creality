from ubuntu:focal

RUN apt-get update
RUN apt-get install -y python3 build-essential gcc-arm-none-eabi sudo srecord

RUN adduser --disabled-password --gecos "" developer && \
  usermod -a -G sudo developer && \
  echo "%sudo ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/nopasswd

USER developer
WORKDIR /home/developer
