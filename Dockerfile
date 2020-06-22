# Using Scala-sbt base image

ARG SBT_BASE_IMAGE_TAG

FROM hseeberger/scala-sbt:${SBT_BASE_IMAGE_TAG:-8u252_1.3.12_2.13.2}

# installing docker from underlying distro, for DinD
RUN apt-get install -y docker.io socat certbot cron
# installing acme.sh
RUN curl https://get.acme.sh | sh

WORKDIR /root
