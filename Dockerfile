# Using Scala-sbt base image

ARG SBT_BASE_IMAGE_TAG

FROM hseeberger/scala-sbt:${SBT_BASE_IMAGE_TAG:-8u252_1.3.12_2.13.2}

# installing docker from underlying distro, for DinD
RUN apt-get install -y docker.io socat certbot cron git make gcc libssl-dev
# installing acme.sh
RUN curl https://get.acme.sh | sh
RUN cp /root/.acme.sh/acme.sh /usr/local/bin/
# installing sscep
RUN git clone https://github.com/certnanny/sscep.git
RUN ln -s /usr/lib/x86_64-linux-gnu openssl
WORKDIR /root/sscep
RUN ./Configure
RUN make
RUN cp /root/sscep/sscep_static /usr/local/bin/
WORKDIR /root
RUN rm -f openssl
RUN rm -rf sscep


WORKDIR /root
