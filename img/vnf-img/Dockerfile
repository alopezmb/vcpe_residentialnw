FROM ubuntu:bionic

#solves hanging timezone input when building image
ENV TZ=Europe/Madrid
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# install required packages
RUN apt-get clean
RUN apt-get update \
    && apt-get install -y  git \
    net-tools \
    aptitude \
    build-essential \
    python-setuptools \
    python-dev \
    python-pip \
    python3-pip \
    software-properties-common \
    ansible \
    curl \
    iptables \
    iputils-ping \
    sudo \
    nano \
    bridge-utils \
    isc-dhcp-server \
    tcpdump \
    openvswitch-switch \
    iperf3 \
    vim \
    ryu-bin \
    iproute2

COPY ipv6_conf .
COPY set-title-vclass set-title-vclass
COPY qos_simple_switch_13.py .
RUN cat set-title-vclass >> ~/.bashrc
RUN cat ipv6_conf >> /etc/sysctl.conf
RUN rm set-title-vclass ipv6_conf

# open ports
# IPERF3
EXPOSE 5201
# IPERF3
EXPOSE 3000
# IPERF3
EXPOSE 7000
