FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y \
    wget \
    curl \
    gnupg \
    lsb-release \
    ca-certificates \
    software-properties-common \
    apache2 \
    supervisor

CMD ["/bin/bash"]
