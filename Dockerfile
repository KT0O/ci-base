# Using Scala-sbt base image

ARG SBT_BASE_IMAGE_TAG

FROM hseeberger/scala-sbt:${SBT_BASE_IMAGE_TAG:-8u252_1.3.12_2.13.2}

# installing docker from underlying distro, for DinD
RUN apt-get install -y docker.io socat certbot cron git make gcc libssl-dev
# installing acme.sh
RUN curl https://get.acme.sh | sh
RUN cp /root/.acme.sh/acme.sh /usr/local/bin/ && \
  rm -rf /root/.acme.sh
# installing sscep
RUN git clone https://github.com/certnanny/sscep.git && \
  ln -s /usr/lib/x86_64-linux-gnu openssl && \
  cd /root/sscep && \
  ./Configure && \
  make && \
  cp /root/sscep/sscep_static /usr/local/bin/sscep && \
  cd /root && \
  rm -f openssl && \
  rm -rf sscep
# cleaning up
RUN apt-get remove -y git gcc libssl-dev

WORKDIR /root
